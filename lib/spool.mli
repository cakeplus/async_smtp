(** Spool directory structure:

   Async_smtp uses a spool directory structure heavily inspired by that of Exim (see [1]
   and [2] for details on that). On startup, async_smtp takes out a lock on the spool
   directory (using the [Lock_file] module with the file $spool_dir/lock) and assumes that
   no other process will be manipulating the files or directories below it without using
   the async_smtp RPC interface.

   The lifetime of a message looks like this:

   When async_smtp accepts a message it immediately processes it, possibly expanding it to
   multiple additional messages (at least one per recipient). Each of the expanded
   messages are added to the spool (by calling [Spool.add]), writing it first to
   $spool_dir/tmp/$msgid (with a timestamp, as well as information about whether the
   message is frozen or not, the last relay attempt, and the parent message ID if any) and
   then renaming it to $spool_dir/active/$msgid (to minimize the chance of a message being
   sent multiple times in case of a crash).

   Newly spooled messages are also immediately written to a queue. A background loop
   iterates over this queue, processing and relaying messages in accordance with the
   [max_concurrent_send_jobs] configuration option. Async_smtp attempts to send each
   message in turn.

   On success, the message is removed from the active directory.

   On failure, the [last_relay_attempt_date] is immediately updated in the on disk spool
   file (again using tmp to make the change as atomic as possible). If the message has any
   remaining retry intervals in [envelope_with_next_hop.retry_intervals] then async_smtp
   schedules a retry for after the interval has elapsed (rewriting the spooled message
   with the interval popped off the list of remaining retry intervals only after the
   interval has elapsed). If there are no remaining retry intervals then the message is
   marked as frozen and moved into $spool_dir/frozen/$msgid (and no further attempts to
   send it are made).

   If async_smtp crashes (or is shutdown) and the spool has contents then it is reloaded
   as follows:

    If there are any contents of $spool_dir/tmp then async_smtp will refuse to
    start. Such messages indicate that mailcore died while changing a message on
    disk, which is a serious problem.

    The contents of $spool_dir/active are read in and re-queued based on the
    last attempted relay time and the remaining retry intervals as above.

   [1] http://www.exim.org/exim-html-current/doc/html/spec_html/ch-how_exim_receives_and_delivers_mail.html
   [2] http://www.exim.org/exim-html-current/doc/html/spec_html/ch-format_of_spool_files.html
*)
open Core.Std
open Async.Std
open Types

module Spooled_message_id : Identifiable

type t

(** Lock the spool directory and load all the files that are already present there. Note
    that for the purposes of locking, the spool directory assumed to NOT be on an NFS file
    system. *)
val create
  :  config:Server_config.t
  -> unit
  -> t Deferred.Or_error.t

(** Immediately write the message to disk and queue it for sending. The
    [Envelope_with_next_hop.t list] represents the different "sections" of one
    message. We make no guarantees about the order of delivery of messages. *)
val add
  :  t
  -> original_msg:Envelope.t
  -> Envelope_with_next_hop.t list
  -> Envelope.Id.t Deferred.Or_error.t

(** [kill_and_flush ~timeout t] makes sure no new delivery sessions are being
    started and waits until all the currently running sessions have finished
    (returning when this is successful or when [timeout] becomes determined). It
    will not affect frozen messages or those waiting for retry intervals to
    elapse. *)
val kill_and_flush
  :  ?timeout:unit Deferred.t
  -> t
  -> [`Finished | `Timeout ] Deferred.t

(** The call [set_max_concurrent_jobs t n] does not affect delivery sessions
    that are already running. Of all the sessions that are started after this
    call only [n] will be allowed to run in parallel. *)
val set_max_concurrent_jobs : t -> int -> unit

val freeze
  :  t
  -> Spooled_message_id.t list
  -> unit Deferred.Or_error.t

val send_now
  :  ?new_retry_intervals : Time.Span.t list
  -> t
  -> Spooled_message_id.t list
  -> unit Deferred.Or_error.t

module Spooled_message_info : sig
  type t with sexp, bin_io

  val id                 : t -> Spooled_message_id.t
  val spool_date         : t -> Time.t
  val last_relay_attempt : t -> (Time.t * Error.t) option
  val parent_id          : t -> Envelope.Id.t
  val status
    : t
    -> [ `Send_now
       | `Send_at of Time.t
       | `Sending
       | `Frozen
       | `Delivered ]

  (* These will not be populated for information obtained using [status].  Use
     [status_from_disk] if you want to see envelopes. Part of the reason is that
     we don't hold envelopes in memory, so we can return status much faster if
     we don't read the disk. A bigger part is that [status] is used to implement
     the rpc call, and we don't want the result to contain sensitive
     information.  *)
  val file_size          : t -> Byte_units.t option
  val envelope           : t -> Envelope.t option
end

module Status : sig
  type t = Spooled_message_info.t list with sexp, bin_io

  val to_formatted_string
    :  t
    -> format : [ `Ascii_table | `Ascii_table_with_max_width of int | `Exim | `Sexp ]
    -> string
end

val status : t -> Status.t
(** This is not necessarily a snapshot of the spool at any given point in time. The only
    way to obtain such a snapshot would be to pause the server and we don't want to do
    that. However, this status will include emails that are stuck on the spool, and those
    are the ones we care about.

    You should not try to work out the total number of unsent messages by counting the
    messages in the status. You should use the [count_from_disk] function instead. *)
val status_from_disk : Server_config.t -> Status.t Deferred.Or_error.t
val count_from_disk : Server_config.t -> int Or_error.t Deferred.t

module Event : sig
  type t = Time.t *
           [ `Spooled   of Spooled_message_id.t
           | `Delivered of Spooled_message_id.t
           | `Frozen    of Spooled_message_id.t
           | `Unfrozen  of Spooled_message_id.t
           | `Ping ]
  with sexp, bin_io

  include Comparable.S with type t := t
  include Hashable.S   with type t := t

  val to_string : t -> string
end

val event_stream
  :  t
  -> Event.t Pipe.Reader.t
