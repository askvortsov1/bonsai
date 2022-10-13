open! Core
open! Bonsai_web
open! Bonsai.Let_syntax
open Incr_map_collate

module Dynamic_cells = struct
  module T = struct
    type ('key, 'data) t =
      | Leaf of
          { leaf_label : Vdom.Node.t Value.t
          ; initial_width : Css_gen.Length.t
          ; cell : key:'key Value.t -> data:'data Value.t -> Vdom.Node.t Computation.t
          ; visible : bool Value.t
          }
      | Group of
          { children : ('key, 'data) t list
          ; group_label : Vdom.Node.t Value.t
          }
      | Org_group of ('key, 'data) t list

    let rec headers = function
      | Leaf { leaf_label; visible; initial_width; cell = _ } ->
        let%map label = leaf_label
        and visible = visible in
        Header_tree.leaf ~label ~visible ~initial_width
      | Group { children; group_label } ->
        let%map label = group_label
        and children = Value.all (List.map children ~f:headers) in
        Header_tree.group ~label children
      | Org_group children ->
        let%map children = List.map children ~f:headers |> Value.all in
        Header_tree.org_group children
    ;;

    let headers t = return (headers t)
    let empty_div = Vdom.Node.div []

    let rec visible_leaves
      : type k v cmp.
        (k * v) Map_list.t Value.t
        -> empty:(k * Vdom.Node.t list) Map_list.t
        -> (k, cmp) Bonsai.comparator
        -> (k, v) t
        -> (k * Vdom.Node.t list) Map_list.t Computation.t list
      =
      fun map ~empty comparator -> function
        | Leaf { cell; visible; _ } ->
          [ (if%sub visible
             then
               Bonsai.Expert.assoc_on
                 (module Map_list.Key)
                 comparator
                 map
                 ~get_model_key:(fun _ (k, _) -> k)
                 ~f:(fun _ data ->
                   let%sub key, data = return data in
                   let%sub r = cell ~key ~data in
                   let%arr key = key
                   and r = r in
                   key, [ r ])
             else (
               let f = Ui_incr.Map.map ~f:(fun (k, _) -> k, [ empty_div ]) in
               Bonsai.Incr.compute map ~f))
          ]
        | Group { children; _ } | Org_group children ->
          List.bind children ~f:(visible_leaves map ~empty comparator)
    ;;

    let instantiate_cells (type k) t comparator (map : (k * _) Map_list.t Value.t) =
      let empty = Map.empty (module Map_list.Key) in
      visible_leaves map ~empty comparator t
      |> Computation.reduce_balanced ~f:(fun a b ->
        Bonsai.Incr.compute (Value.both a b) ~f:(fun a_and_b ->
          let%pattern_bind.Ui_incr a, b = a_and_b in
          Ui_incr.Map.merge a b ~f:(fun ~key:_ change ->
            match change with
            | `Left l -> Some l
            | `Right r -> Some r
            | `Both ((i, l), (_, r)) -> Some (i, l @ r))))
      |> Option.value ~default:(Bonsai.const empty)
    ;;
  end

  type ('key, 'data) t = ('key, 'data) T.t

  let column ?(initial_width = `Px 50) ?(visible = Value.return true) ~label ~cell () =
    T.Leaf { leaf_label = label; initial_width; cell; visible }
  ;;

  let group ~label children = T.Group { group_label = label; children }
  let expand ~label child = group ~label [ child ]

  let lift : type key data. (key, data) T.t list -> (key, data) Column_intf.t =
    let module X = struct
      type t = (key, data) T.t
      type nonrec key = key
      type nonrec data = data

      let headers = T.headers
      let instantiate_cells = T.instantiate_cells
    end
    in
    fun columns ->
      let value = T.Org_group columns in
      Column_intf.T { value; vtable = (module X) }
  ;;
end

module Dynamic_columns = struct
  module T = struct
    type ('key, 'data) t =
      | Leaf of
          { leaf_label : Vdom.Node.t
          ; initial_width : Css_gen.Length.t
          ; cell : key:'key -> data:'data -> Vdom.Node.t
          ; visible : bool
          }
      | Group of
          { children : ('key, 'data) t list
          ; group_label : Vdom.Node.t
          }
      | Org_group of ('key, 'data) t list

    let rec translate = function
      | Leaf { leaf_label = label; initial_width; visible; cell = _ } ->
        Header_tree.leaf ~label ~visible ~initial_width
      | Group { children; group_label = label } ->
        let children = List.map children ~f:translate in
        Header_tree.group ~label children
      | Org_group children -> Header_tree.org_group (List.map children ~f:translate)
    ;;

    let headers t = Bonsai.pure translate t

    let rec visible_leaves structure ~key ~data =
      match structure with
      | Leaf { cell; visible; _ } -> if visible then [ cell ~key ~data ] else []
      | Org_group children | Group { children; group_label = _ } ->
        List.concat_map children ~f:(visible_leaves ~key ~data)
    ;;

    let instantiate_cells t _comparator map =
      Bonsai.Incr.compute (Bonsai.Value.both t map) ~f:(fun both ->
        let%pattern_bind.Ui_incr t, map = both in
        (* Why is this bind here ok?  Well, there is an alternative that involves
           Incr_map.mapi' which closes over visible_leaves as an incremental, but even
           in that scenario, if the set of visible_leaves changes, we're recomputing the
           whole world anyway, so it doesn't buy us anything vs this bind. *)
        let%bind.Ui_incr visible_leaves = Ui_incr.map t ~f:visible_leaves in
        Ui_incr.Map.map map ~f:(fun (key, data) -> key, visible_leaves ~key ~data))
    ;;
  end

  type ('key, 'data) t = ('key, 'data) T.t

  let column ?(initial_width = `Px 50) ?(visible = true) ~label ~cell () =
    T.Leaf { leaf_label = label; initial_width; cell; visible }
  ;;

  let group ~label children = T.Group { group_label = label; children }
  let expand ~label child = group ~label [ child ]

  let lift : type key data. (key, data) T.t list Value.t -> (key, data) Column_intf.t =
    let module X = struct
      type t = (key, data) T.t Value.t
      type nonrec key = key
      type nonrec data = data

      let headers = T.headers
      let instantiate_cells = T.instantiate_cells
    end
    in
    fun columns ->
      let value =
        let%map columns = columns in
        T.Org_group columns
      in
      Column_intf.T { value; vtable = (module X) }
  ;;
end

module With_sorter (Tree : T2) (Container : T1) = struct
  type ('key, 'data) t =
    | Leaf of
        { t : ('key, 'data) Tree.t
        ; sort : ('key * 'data -> 'key * 'data -> int) Container.t
        }
    | Group of
        { build : ('key, 'data) Tree.t list -> ('key, 'data) Tree.t
        ; children : ('key, 'data) t list
        }

  let rec partition i sorters_acc ~f = function
    | Leaf { t = inside; sort } ->
      let sorters_acc = Map.add_exn (sorters_acc : _ Int.Map.t) ~key:i ~data:sort in
      let t = f i sort inside in
      let i = i + 1 in
      i, sorters_acc, t
    | Group { build; children } ->
      let (i, sorters_acc), children =
        List.fold_map children ~init:(i, sorters_acc) ~f:(fun (i, sorters_acc) child ->
          let i, sorters_acc, child = partition i sorters_acc ~f child in
          (i, sorters_acc), child)
      in
      i, sorters_acc, build children
  ;;

  let partition t ~f =
    let _, sorters, tree = partition 0 Int.Map.empty ~f t in
    sorters, tree
  ;;
end

module Dynamic_cells_with_sorter = struct
  module Container = struct
    type 'a t = 'a option Value.t
  end

  module T = With_sorter (Dynamic_cells.T) (Container)

  type ('key, 'data) t = ('key, 'data) T.t

  let column ?sort ?initial_width ?visible ~label ~cell () =
    let sort =
      match sort with
      | None -> Value.return None
      | Some x -> x >>| Option.some
    in
    T.Leaf { sort; t = Dynamic_cells.column ?initial_width ?visible ~label ~cell () }
  ;;

  let group ~label children = T.Group { build = Dynamic_cells.group ~label; children }
  let expand ~label child = group ~label [ child ]

  module W = struct
    let headers_and_sorters t sortable_header =
      let sorters, tree =
        T.partition t ~f:(fun i sort -> function
          | Dynamic_cells.T.Leaf { leaf_label; initial_width; cell; visible } ->
            let leaf_label =
              let%map leaf_label = leaf_label
              and has_sorter = sort >>| Option.is_some
              and sortable_header = sortable_header in
              if has_sorter
              then Sortable_header.decorate sortable_header leaf_label i
              else
                Vdom.Node.div [ leaf_label ]
            in
            Dynamic_cells.T.Leaf { leaf_label; initial_width; cell; visible }
          | other -> (* This should never happen *) other)
      in
      let sorters =
        sorters
        |> Map.to_alist
        |> List.map ~f:(fun (i, sorter) ->
          let%map sorter = sorter in
          Option.map sorter ~f:(fun sorter -> i, sorter))
        |> Value.all
        >>| Fn.compose Int.Map.of_alist_exn List.filter_opt
      in
      let%sub headers = Dynamic_cells.T.headers tree in
      return (Value.both sorters headers)
    ;;

    let instantiate_cells t =
      let _sorters, tree = T.partition t ~f:(fun _i _sort -> Fn.id) in
      Dynamic_cells.T.instantiate_cells tree
    ;;
  end

  let lift : type key data. (key, data) T.t list -> (key, data) Column_intf.with_sorter =
    let module X = struct
      type t = (key, data) T.t
      type nonrec key = key
      type nonrec data = data

      include W
    end
    in
    fun columns ->
      let value =
        T.Group { children = columns; build = (fun c -> Dynamic_cells.T.Org_group c) }
      in
      Column_intf.Y { value; vtable = (module X) }
  ;;
end

module Dynamic_columns_with_sorter = struct
  module T = With_sorter (Dynamic_columns.T) (Option)

  type ('key, 'data) t = ('key, 'data) T.t

  let column ?sort ?initial_width ?visible ~label ~cell () =
    T.Leaf { sort; t = Dynamic_columns.column ?initial_width ?visible ~label ~cell () }
  ;;

  let group ~label children = T.Group { build = Dynamic_columns.group ~label; children }
  let expand ~label child = group ~label [ child ]

  module W = struct
    let headers_and_sorters t sortable_header =
      let%sub sorters, tree =
        let%arr t = t
        and sortable_header = sortable_header in
        let sorters, tree =
          T.partition t ~f:(fun i sorter -> function
            | Dynamic_columns.T.Leaf { leaf_label; initial_width; cell; visible } ->
              let leaf_label =
                match sorter with
                | Some _ -> Sortable_header.decorate sortable_header leaf_label i
                | None -> Vdom.Node.div [ leaf_label ] ~attr:Vdom.Attr.empty
              in
              Dynamic_columns.T.Leaf { leaf_label; initial_width; cell; visible }
            | other -> (* This should never happen *) other)
        in
        let sorters =
          sorters
          |> Map.to_alist
          |> List.filter_map ~f:(fun (i, sorter) ->
            Option.map sorter ~f:(fun sorter -> i, sorter))
          |> Int.Map.of_alist_exn
        in
        sorters, tree
      in
      let%sub headers = Dynamic_columns.T.headers tree in
      return (Value.both sorters headers)
    ;;

    let instantiate_cells t =
      let tree =
        let%map t = t in
        let _sorters, tree = T.partition t ~f:(fun _i _sort -> Fn.id) in
        tree
      in
      Dynamic_columns.T.instantiate_cells tree
    ;;
  end

  let lift
    : type key data. (key, data) T.t list Value.t -> (key, data) Column_intf.with_sorter
    =
    let module X = struct
      type t = (key, data) T.t Value.t
      type nonrec key = key
      type nonrec data = data

      include W
    end
    in
    fun columns ->
      let value =
        let%map columns = columns in
        T.Group { children = columns; build = (fun c -> Dynamic_columns.T.Org_group c) }
      in
      Column_intf.Y { value; vtable = (module X) }
  ;;
end

