package main

import "core:fmt"
import "core:strings"
import "core:math"
import sdl "vendor:sdl3"
import "core:container/queue"
import sdlMix "vendor:sdl3/mixer"
import sdlTtf "vendor:sdl3/ttf"

SdlState :: struct {
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    mixer: ^sdlMix.Mixer,
    current_audio: ^sdlMix.Audio,
    track: ^sdlMix.Track,
    ttf_engine: ^sdlTtf.TextEngine,
    font: ^sdlTtf.Font,
    song_list: queue.Queue(^sdlMix.Audio),
    current_track_data: TrackData,
}

TrackData :: struct {
    title: cstring,
    artist: cstring,
    album: cstring,
}

handle_key :: proc(sdl_state: ^SdlState, key_event: ^sdl.Event) {
    switch key_event.key.key {
    case sdl.K_SPACE: {
        toggle_pause(sdl_state)
    }
    case sdl.K_F: {
        if queue.len(sdl_state.song_list) != 0 {
            play_next_song(sdl_state)
        }
    }
    }
}

load_dropped_audio_file :: proc(sdl_state: ^SdlState, file_path: cstring) {
    path_info: sdl.PathInfo
    if !sdl.GetPathInfo(file_path, &path_info) {
        panic(string(sdl.GetError()))
    }
    if path_info.type == .FILE {
        audio := sdlMix.LoadAudio(sdl_state.mixer, file_path, false)
        queue.push_back(&sdl_state.song_list, audio)
    } else if path_info.type == .DIRECTORY {
        count: i32
        songs := sdl.GlobDirectory(file_path, "*", {}, &count)
        for song in ([^]cstring)(songs)[:count] {
            path := strings.concatenate({string(file_path), "/", string(song)})
            defer delete(path)
            song_path := strings.clone_to_cstring(path)
            defer delete(song_path)
            audio := sdlMix.LoadAudio(sdl_state.mixer, song_path, false)
            queue.push_back(&sdl_state.song_list, audio)
        }
    }
}

create_audio_properties :: proc(audio: ^sdlMix.Audio) -> TrackData {
    data: TrackData
    properties := sdlMix.GetAudioProperties(audio)
    data.title = sdl.GetStringProperty(properties, sdlMix.PROP_METADATA_TITLE_STRING, "Unknown Title")
    data.artist = sdl.GetStringProperty(properties, sdlMix.PROP_METADATA_ARTIST_STRING, "Unknown Artist")
    data.album = sdl.GetStringProperty(properties, sdlMix.PROP_METADATA_ALBUM_STRING, "Unknown Album")
    return data
}

init_functions :: proc() {
    if !sdl.Init({.EVENTS, .VIDEO, .AUDIO}) {
        panic(string(sdl.GetError()))
    }
    if !sdlMix.Init() {
        panic(string(sdl.GetError()))
    }
    if !sdlTtf.Init() {
        fmt.eprintln("failed to init ttf: ", sdl.GetError())
        panic(string(sdl.GetError()))
    }
}

// function draws text and returns the rectangle that contains the text for further manipulations
draw_text :: proc(sdl_state: SdlState, text: cstring, rect: ^sdl.FRect) {
    drawing_text := sdlTtf.CreateText(sdl_state.ttf_engine,
                                      sdl_state.font,
                                      raw_data(string(text)),
                                      0)
    w: i32 = 0
    h: i32 = 0
    sdlTtf.GetTextSize(drawing_text, &w, &h)
    rect.w = auto_cast w
    rect.h = auto_cast h
    sdlTtf.DrawRendererText(drawing_text, rect.x, rect.y)
    sdlTtf.DestroyText(drawing_text)
}

sdl_state_init :: proc(sdl_state: ^SdlState) {
    sdl_state.window = sdl.CreateWindow("audio player", 800, 600, {})
    sdl_state.renderer = sdl.CreateRenderer(sdl_state.window, nil)
    sdl_state.mixer = sdlMix.CreateMixerDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
    sdl_state.track = sdlMix.CreateTrack(sdl_state.mixer)
    sdl_state.ttf_engine = sdlTtf.CreateRendererTextEngine(sdl_state.renderer)
    sdl_state.font = sdlTtf.OpenFont(cstring("/Users/jacobwong/Library/Fonts/PersonalIosevka-Regular.ttf"), 16)
    queue.init(&sdl_state.song_list)
}

// enter mouse coordinates and check if in region
check_mouse_in_region :: proc(pos: [2]f32, rect: sdl.FRect) -> bool {
    return math.abs(pos.x - rect.x) <= rect.w && math.abs(pos.y - rect.y) <= rect.h
}

get_mouse_pos :: proc() -> (f32, f32) {
    x: f32 = 0
    y: f32 = 0
    mouse_flags :=  sdl.GetMouseState(&x, &y)
    return x, y
}

play_next_song :: proc(sdl_state: ^SdlState) {
    sdl_state.current_audio = queue.pop_front(&sdl_state.song_list)
    sdl_state.current_track_data = create_audio_properties(sdl_state.current_audio)
    if !sdlMix.SetTrackAudio(sdl_state.track, sdl_state.current_audio) {
        panic("failed to set track")
    }
    if !sdlMix.PlayTrack(sdl_state.track, 0) {
        panic("failed to play track")
    }
}

draw_playback_time :: proc(sdl_state: SdlState) {
    playback_time := sdlMix.TrackFramesToMS(sdl_state.track, sdlMix.GetTrackPlaybackPosition(sdl_state.track)) / 1000
    playback_min := (playback_time % 3600) / 60
    playback_sec := playback_time % 60
    playback_str := fmt.tprintf("%02d:%02d", playback_min, playback_sec)

    total_time := sdlMix.TrackFramesToMS(sdl_state.track, sdlMix.GetAudioDuration(sdl_state.current_audio)) / 1000
    total_min := (total_time % 3600) / 60
    total_sec := total_time % 60
    time_str := fmt.tprintf("%02d:%02d", total_min, total_sec)

    final_str := fmt.tprint(playback_str, "/", time_str)
    final_cstr := strings.clone_to_cstring(final_str, context.temp_allocator)

    draw_text(sdl_state, final_cstr, &{100, 250, 0, 0})
}

toggle_pause :: proc(sdl_state: ^SdlState) {
    if sdlMix.TrackPlaying(sdl_state.track) {
        if !sdlMix.PauseTrack(sdl_state.track) {
            fmt.eprintln("failed to pause track")
            return
        }
    } else {
        if !sdlMix.ResumeTrack(sdl_state.track) {
            fmt.eprintln("failed to continue track")
            return
        }
    }
}

main :: proc() {
    init_functions()
    defer {
        sdlMix.Quit()
        sdlTtf.Quit()
        sdl.Quit()
    }

    sdl_state: SdlState

    sdl_state_init(&sdl_state)

    window_should_close := false
    color := sdl.Color{30, 30, 30, 255}

    for !window_should_close {
        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT: {
                    window_should_close = true;
                }
                case .DROP_FILE: {
                    file_path: cstring = event.drop.data
                    load_dropped_audio_file(&sdl_state, file_path)
                }
                case .KEY_DOWN: {
                    handle_key(&sdl_state, &event)
                }
                case .MOUSE_BUTTON_DOWN: {
                    if event.button.button == sdl.BUTTON_LEFT {
                        // x, y := get_mouse_pos()
                    }
                }
            }
        }

        sdl.SetRenderDrawColor(sdl_state.renderer, color.r, color.g, color.b, color.a)
        sdl.RenderClear(sdl_state.renderer)

        if (queue.len(sdl_state.song_list) != 0) {
            if (!sdlMix.TrackPlaying(sdl_state.track) && !sdlMix.TrackPaused(sdl_state.track)) {
                play_next_song(&sdl_state)
            }
        }

        if sdl_state.current_track_data != {} {
            draw_text(sdl_state, sdl_state.current_track_data.title, &{100, 100, 0, 0})
            draw_text(sdl_state, sdl_state.current_track_data.artist, &{100, 150, 0, 0})
            draw_text(sdl_state, sdl_state.current_track_data.album, &{100, 200, 0, 0})

            draw_playback_time(sdl_state)
            draw_text(sdl_state, sdlMix.TrackPlaying(sdl_state.track) ? "playing" : "paused", &{100, 300, 0, 0})
        }

        sdl.RenderPresent(sdl_state.renderer)
    }
}
