open Core.Std
open Async.Std
open Types

module Callbacks = Server_callbacks

type t

val start : config:Server_config.t -> (module Server_callbacks.S) -> t Deferred.Or_error.t

val config : t -> Server_config.t

val close  : ?timeout:unit Deferred.t -> t -> unit Deferred.Or_error.t

(* Read messages from a bsmtp session transcript. *)
val read_bsmtp
  :  Reader.t
  -> Envelope.t Or_error.t Pipe.Reader.t

val read_mbox
  :  Reader.t
  -> Envelope.t Or_error.t Pipe.Reader.t

val ports : t -> int list
