[@@@js.dummy "!! This code has been generated by gen_js_api !!"]
[@@@ocaml.warning "-7-32-39"]
open! Core
open! Import
open Gen_js_api
type t = [ `y1  | `y2 ]
let rec t_of_js : Ojs.t -> t =
  fun (x2 : Ojs.t) ->
    let x3 = x2 in
    match Ojs.string_of_js x3 with
    | "y1" -> `y1
    | "y2" -> `y2
    | _ -> assert false
and t_to_js : t -> Ojs.t =
  fun (x1 : [ `y1  | `y2 ]) ->
    match x1 with
    | `y1 -> Ojs.string_to_js "y1"
    | `y2 -> Ojs.string_to_js "y2"
