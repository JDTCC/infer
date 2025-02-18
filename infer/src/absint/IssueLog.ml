(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(** Module to store a set of issues per procedure *)

open! IStd

type t = Errlog.t Procname.Map.t

let empty = Procname.Map.empty

let get_or_add ~proc m =
  match Procname.Map.find_opt proc m with
  | Some errlog ->
      (m, errlog)
  | None ->
      let errlog = Errlog.empty () in
      let m = Procname.Map.add proc errlog m in
      (m, errlog)


module SQLite = SqliteUtils.MarshalledDataNOTForComparison (struct
  type nonrec t = t
end)

let store ~checker ~file m =
  if not (Procname.Map.is_empty m) then
    DBWriter.store_issue_log ~checker:(Checker.get_id checker)
      ~source_file:(SourceFile.SQLite.serialize file)
      ~issue_log:(SQLite.serialize m)


let iter_issue_logs =
  let select_statement =
    Database.register_statement AnalysisDatabase "SELECT checker, issue_log FROM issue_logs"
  in
  fun ~f ->
    Database.with_registered_statement select_statement ~f:(fun db stmt ->
        SqliteUtils.result_fold_rows ~init:() ~finalize:false db ~log:"IssueLog.fold_issue_logs"
          stmt ~f:(fun () stmt ->
            let checker : Checker.t =
              match[@warning "-8"] Sqlite3.column stmt 0 with
              | Sqlite3.Data.TEXT checker_str ->
                  Checker.from_id checker_str |> Option.value_exn
            in
            let issue_log : t = Sqlite3.column stmt 1 |> SQLite.deserialize in
            f checker issue_log ) )


let iter_all_issues ~f =
  iter_issue_logs ~f:(fun checker issue_log ->
      Procname.Map.iter (fun procname errlog -> f checker procname errlog) issue_log )
