open Core.Std
open Async.Std
open Async_smtp.Std
open Email_message.Std

let main () =
  let stdin  = Lazy.force Reader.stdin in
  let stdout = Lazy.force Writer.stdout in
  let pipe =
    Smtp_server.read_bsmtp stdin
    |> Pipe.map ~f:Or_error.ok_exn
  in
  Pipe.iter_without_pushback pipe ~f:(fun m ->
    let email = Smtp_envelope.email m in
    Writer.write stdout (Sexp.to_string_hum (Email.sexp_of_t email)))
  >>= fun () ->
  Writer.flushed stdout
;;

let parse =
  Command.async
    ~summary:("Parse BSMTP from stdin and output as sexp")
    Command.Spec.empty
    main

let command : Command.t =
  Command.group
    ~summary:"BSMTP tools"
    [ "parse", parse
    ]
;;
