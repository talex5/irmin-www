
(* Copyright (C) 2015, Thomas Leonard
 * See the README file for details. *)

open Lwt
open V1_LWT

let () = Log.(set_log_level INFO)

let irmin_uri = Uri.of_string "http://127.0.0.1:8081"

(* Never used, but needed to create the store. *)
let task s = Irmin.Task.create ~date:0L ~owner:"Server" s

module Context = struct
  let v () = failwith "Context"
end

module Mirage_git_memory = Irmin_mirage.Irmin_git.Memory(Context)(Git.Inflate.None)
module Store = Irmin.Basic(Mirage_git_memory)(Irmin.Contents.String)
let config = Irmin_mem.config ()

(*
module Store = Irmin.Basic(Irmin_unix.Irmin_git.FS)(Irmin.Contents.String)
let config = Irmin_unix.Irmin_git.config ~root:"db" ()
*)

module Bundle = Tc.Pair(Store.Private.Slice)(Store.Head)

module Irmin_server = struct
  module X = struct
    include Cohttp_lwt_unix.Server
    let listen t ?timeout uri =
      let port = match Uri.port uri with
        | None   -> 8081
        | Some p -> p in
      create ?timeout ~mode:(`TCP (`Port port)) t
  end
  module Y = struct
    let pretty d =
      let tm = Unix.localtime (Int64.to_float d) in
      Printf.sprintf "%02d:%02d:%02d"
        tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
  end

  include Irmin_http_server.Make(X)(Y)(Store)
end

(* Split a URI into a list of path segments *)
let split_path path =
  let rec aux = function
    | [] | [""] -> []
    | hd::tl -> hd :: aux tl
  in
  List.filter (fun e -> e <> "")
    (aux (Re_str.(split_delim (regexp_string "/") path)))

module Main (Stack:STACKV4) = struct
  module TCP  = Stack.TCPV4
  module S = Cohttp_mirage.Server(TCP)

  let handle_request s _conn_id request _body =
    let path = Uri.path (Cohttp.Request.uri request) in
    let s = s path in
    let ps = split_path path in
    Store.read s ps >>= function
    | Some body -> S.respond_string ~status:`OK ~body ()
    | None ->
        Store.read s (ps @ ["index.html"]) >>= function
        | Some body -> S.respond_string ~status:`OK ~body ()
        | None ->
            S.respond_error ~status:`Not_found ~body:(Printf.sprintf "File '%s' does not exist" path) ()

  let dump s =
    let s = s "export" in
    Store.head s >>= function
    | None -> failwith "dump: no head!"
    | Some head ->
    Store.export ~max:[head] s >>= fun slice ->
    let bundle = (slice, head) in
    let buf = Cstruct.create (Bundle.size_of bundle) in
    let rest = Bundle.write bundle buf in
    assert (Cstruct.len rest = 0);
    let path = "init_db.ml" in
    Printf.printf "Writing %s...\n%!" path;
    let ch = open_out_bin path in
    Printf.fprintf ch "let init_db = %S" (Cstruct.to_string buf);
    close_out ch;
    Printf.printf "Wrote %s\n%!" path;
    return ()

  let import s db =
    let s = s "import" in
    let buf = Mstruct.of_string db in
    let (slice, head) = Bundle.read buf in
    Store.import s slice >>= function
    | `Error -> failwith "Irmin import failed"
    | `Ok ->
    Store.fast_forward_head s head >>= function
    | false -> failwith "Irmin import failed at FF"
    | true -> return ()

  let start stack =
    Store.create config task >>= fun s ->
(*     dump s >>= fun () -> *)
    import s Init_db.init_db >>= fun () ->
    let http = S.make ~conn_closed:ignore ~callback:(handle_request s) () in
    Stack.listen_tcpv4 stack ~port:8080 (fun flow ->
      let peer, port = TCP.get_dest flow in
      Log.info "Connection from %s (client port %d)" (Ipaddr.V4.to_string peer) port;
      S.listen http flow >>= fun () ->
      TCP.close flow
    );
    Lwt.async (fun () ->
      Irmin_server.listen (s "server") ~strict:true irmin_uri
    );
    Stack.listen stack
end
