
(* Copyright (C) 2015, Thomas Leonard
 * See the README file for details. *)

open Lwt
open V1_LWT

let () = Log.(set_log_level INFO)

let irmin_uri = Uri.of_string "https://127.0.0.1:8444"

(* Never used, but needed to create the store. *)
let task s = Irmin.Task.create ~date:0L ~owner:"Server" s

module Context = struct
  let v () = failwith "Context"
end

module Hash = Irmin.Hash.SHA1
module Mirage_git_memory = Irmin_mirage.Irmin_git.Memory(Context)(Git.Inflate.None)
module Store = Irmin_mem.Make(Irmin.Contents.String)(Irmin.Ref.String)(Hash)
let config = Irmin_mem.config ()

(*
module Store = Irmin.Basic(Irmin_unix.Irmin_git.FS)(Irmin.Contents.String)
let config = Irmin_unix.Irmin_git.config ~root:"db" ()
*)

module Bundle = Tc.Pair(Store.Private.Slice)(Hash)

(* Split a URI into a list of path segments *)
let split_path path =
  let rec aux = function
    | [] | [""] -> []
    | hd::tl -> hd :: aux tl
  in
  List.filter (fun e -> e <> "")
    (aux (Re_str.(split_delim (regexp_string "/") path)))

module Main (Stack:STACKV4) (Conf:KV_RO) (Clock:V1.CLOCK) = struct
  module TCP  = Stack.TCPV4
  module TLS  = Tls_mirage.Make (TCP)
  module X509 = Tls_mirage.X509 (Conf) (Clock)
  module S = Cohttp_mirage.Server(TLS)

  (* Take a new raw flow, perform a TLS handshake to get a TLS flow and call [f tls_flow].
     When done, the underlying flow will be closed in all cases. *)
  let wrap_tls tls_config f flow =
    let peer, port = TCP.get_dest flow in
    Log.info "Connection from %s (client port %d)" (Ipaddr.V4.to_string peer) port;
    TLS.server_of_flow tls_config flow >>= function
    | `Error _ -> Log.warn "TLS failed"; TCP.close flow
    | `Eof     -> Log.warn "TLS eof"; TCP.close flow
    | `Ok flow  ->
        Lwt.finalize
          (fun () -> f flow)
          (fun () -> TLS.close flow)

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
      let r = Store.repo s in
      Store.Repo.export ~max:[head] r >>= fun slice ->
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

  let make_source () =
    let contents = "<body><h1>It works!</h1></body>" in
    let path = ["index.html"] in
    Store.Repo.create config >>= fun r ->
    Store.master task r >>= fun s ->
    Store.update (s "Default site") path contents >>= fun () ->
    dump s

  let import s db =
    let s = s "import" in
    let buf = Mstruct.of_string db in
    Printf.printf "db: [%s]\n" db;
    Printf.printf "before bundle.read\n";
    let (slice, head) = Bundle.read buf in
    Printf.printf "after bundle.read\n";
    let r = Store.repo s in
    Store.Repo.import r slice >>= function
    | `Error -> failwith "Irmin import failed"
    | `Ok ->
    Store.fast_forward_head s head >>= function
    | false -> failwith ("Irmin import failed at fast-forward for head " ^
                         (Hash.to_hum head))
    | true -> return ()

  let start stack conf _clock =
    X509.certificate conf `Default >>= fun cert ->
    let tls_config = Tls.Config.server ~certificates:(`Single cert) () in
    Store.Repo.create config >>= fun r ->
    Printf.printf "mark 1\n";
    Store.master task r >>= fun s ->
    Printf.printf "mark 2\n";
    import s Init_db.init_db >>= fun () ->
    Printf.printf "mark 3\n";
    let http = S.make ~conn_closed:ignore ~callback:(handle_request s) () in
    Printf.printf "mark 4\n";
    Stack.listen_tcpv4 stack ~port:8443 (wrap_tls tls_config (S.listen http));
    Printf.printf "mark 5\n";
    let module Irmin_server = struct
      (* We have to define this here because we need [stack] in scope
         * for [listen]. Perhaps it would make more sense for [Irmin_http_server]
         * to return the spec, rather than calling [listen] itself? *)
      module X = S
      module Y = struct
        let pretty d =
          Printf.sprintf "%Ld" d
      end

      include Irmin_http_server.Make(X)(Y)(Store)
    end in
    let spec = Irmin_server.http_spec (s "server") ~strict:true in
    Stack.listen_tcpv4 stack ~port:8444 (wrap_tls tls_config (S.listen spec));
    Stack.listen stack
end
