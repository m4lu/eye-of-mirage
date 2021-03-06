(* Copyright (C) 2016, Thomas Leonard
   See the README file for details. *)

open Rresult
open Lwt.Infix

let src = Logs.Src.create "eye-of-mirage" ~doc:"Eye of Mirage main module"
module Log = (val Logs.src_log src : Logs.LOG)

module Main
    (Time: Mirage_time_lwt.S)
=
struct

module Eyeofmirage(FB : Framebuffer.S)=
struct
  module Img = Framebuffer_image.Make(FB)

  let image_ptr = ref 0
  let images = (let a = Array.of_list Myfiles.file_list in Array.sort compare a;a )
  let switch_image step =
    let count = Array.length images in
    image_ptr := (abs (!image_ptr + count + step)) mod count;
    images.(!image_ptr)

  let next_image () : string = switch_image 1
  let prev_image () : string = switch_image (-1)

  let steps () = Lwt.return_unit (*
    Time.sleep_ns 1_000_000_L >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Time.sleep_ns 1_000_000_L >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit >>= fun () ->
    Lwt.return_unit*)

  let paint_embedded name fb =
    let image =
      let raw = match Myfiles.read name with Some v -> v
                                           | None -> assert false in
      (* ^-- TODO this duplicates it in memory, read chunks instead *)
      let x : ImageUtil.chunk_reader =
        let pos = ref (0) in
        function
        | `Close -> Ok ""
        | `Bytes b ->
          let end_pos = !pos + b in
          if end_pos > String.length raw then raise End_of_file
          else begin
            let ret = String.sub raw !pos b in pos := end_pos ;
            Ok ret
          end
      in
      ImageLib.PNG.ReadPNG.parsefile x
    in
    Lwt.try_bind
      (fun () ->
         FB.resize ~width:image.Image.width ~height:image.Image.height fb
         >>= fun () -> Logs.debug(fun m -> m "resizing"); Lwt.return_unit)
      (fun () -> steps () )
      (fun _ -> failwith "FB resize failed")  >>= fun () ->
    Img.draw_image fb image ;
    FB.redraw fb >>= fun () ->
    Lwt.return fb

  let rec input_loop fb =
    Time.sleep_ns 1_000_000_L >>= fun () ->
    let open Framebuffer__S in
    FB.recv_event fb >>= function
    | Window_close -> Lwt.return_unit
    | Keypress {pressed = true; keysym; mods; _} as event ->
      Log.info (fun m -> m "Keypress: %a" Framebuffer.pp_backend_event event);
      let open Framebuffer__Keycodes in
      begin match keysym, mods with
        | None , _ -> Lwt.return_unit
        | Some (`Left_Arrow), _ ->
          paint_embedded (prev_image ()) fb >>= fun _ -> Lwt.return_unit
        | Some (`Right_Arrow|`Space), _ ->
          paint_embedded (next_image ()) fb >>= fun _ -> Lwt.return_unit
      | Some ks , kmods ->
        Log.app (fun m -> m "parsed keysym: %a; %a; %a"
                   Framebuffer__Keycodes.pp_keysym ks
                   Fmt.(list ~sep:(unit "; ") pp_kmod) kmods
                   Fmt.(list ~sep:(unit ", ") char)
                   (US_keyboard.to_unicode kmods ks |> List.map Uchar.to_char)
                ); Lwt.return_unit
      end >>= fun () -> input_loop fb
    | event ->
      Log.info (fun m -> m "Iterated loop: %a"
                   Framebuffer.pp_backend_event event);
    input_loop fb

  let start () =
    Log.info (fun f -> f "Starting");

    Lwt.try_bind
      (fun () -> FB.window ~width:300 ~height:300)
      (fun fb -> Lwt.return fb)
      (fun _ -> failwith "FB init failed")  >>= fun fb ->
    paint_embedded (switch_image 0) fb >>= fun fb ->
    (*FB.letters fb ~x:30 ~y:30 "a" >>= fun () ->*)
    let red = FB.compile_rgb ~r:'\xff' fb in
    let green = FB.compile_rgb ~g:'\xff' fb in
    let blue = FB.compile_rgb ~b:'\xff' fb in
    let cyan = FB.compile_rgb ~g:'\xff' ~b:'\xff' fb in
    let black = FB.compile_rgb fb in
    let line = FB.compile_line [cyan;red;red;red;green;green;green;blue] fb in
    FB.pixel fb ~x:10 ~y:10 red ;
    FB.pixel fb ~x:12 ~y:10 green ;
    FB.pixel fb ~x:14 ~y:10 blue ;
    FB.pixel fb ~x:16 ~y:10 black ;
    FB.pixel fb ~x:17 ~y:10 black ;
    FB.pixel fb ~x:16 ~y:11 black ;
    FB.pixel fb ~x:17 ~y:11 black ;
    (*FB.pixel fb ~x:10 ~y:10 red >>= fun()->
    FB.rect_lineiter fb ~x:15 ~y:10 ~y_end:11 (fun _ -> line) >>= fun () ->*)
    (*FB.letters fb ~x:50 ~y: 50 "Hello, MF#K world!" >>= fun () ->*)
    FB.redraw fb >>= fun () ->
    input_loop fb
end

let start _time (fb_init: unit -> ('a * (module Framebuffer.S) Lwt.t) Lwt.t) =
  fb_init () >>= fun (_platform_specific, fb_promise) ->
  fb_promise >>= fun fb_module ->
  let module FB : Framebuffer.S= (val (fb_module) : Framebuffer.S) in
  let module App = Eyeofmirage(FB) in
  App.start ()

end
