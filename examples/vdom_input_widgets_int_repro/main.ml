open! Core
open! Bonsai_web
open Bonsai.Let_syntax

let component
      (type a)
      (module M : Bonsai.Model with type t = a)
      ~name
      ~some_constant_value
      ~node_creator
  =
  let%sub textbox_state = Bonsai.state_opt (module M) in
  let%arr state, set_state = textbox_state in
  let input = node_creator state set_state in
  let debug = state |> [%sexp_of: M.t option] |> Sexp.to_string_hum |> Vdom.Node.text in
  let clear_button =
    Vdom.Node.button
      ~attr:(Vdom.Attr.on_click (fun _ -> set_state None))
      [ Vdom.Node.text "clear" ]
  in
  let set_constant =
    Vdom.Node.button
      ~attr:(Vdom.Attr.on_click (fun _ -> set_state (Some some_constant_value)))
      [ Vdom.Node.text "set constant" ]
  in
  Vdom.Node.div [ Vdom.Node.text name; input; clear_button; set_constant; debug ]
;;

let component =
  let%sub number_input =
    component
      (module Int)
      ~name:"interger based"
      ~some_constant_value:1000
      ~node_creator:(fun value on_input ->
        Vdom_input_widgets.Entry.number
          ~merge_behavior:Legacy_dont_merge
          (module Int)
          ~value
          ~on_input
          ~step:1.)
  in
  let%sub string_input =
    component
      (module String)
      ~name:"string based"
      ~some_constant_value:"hello world"
      ~node_creator:(fun value on_input ->
        Vdom_input_widgets.Entry.text
          ~merge_behavior:Legacy_dont_merge
          ~value
          ~on_input
          ())
  in
  let%arr number_input = number_input
  and string_input = string_input in
  Vdom.Node.div [ number_input; string_input ]
;;

let () = Bonsai_web.Start.start component
