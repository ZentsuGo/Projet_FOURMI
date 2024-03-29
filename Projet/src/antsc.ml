open Printf;;


let clean_temp () : int = Sys.command "rm -f *.temp"

let handle_sig (signal:int) : unit= match signal with
  |s when s = Sys.sigint -> let _ = clean_temp () in exit 2
  |_ -> failwith "Unexcepted handling of signal\n" 

let process_file filename =
  (* Ouvre le fichier et créé un lexer. *)
  let file = open_in filename in
  let lexer = Lexer.of_channel file in
  (* Parse le fichier. *)
  let (program, span) = Parser.parse_program lexer in
  (* printf "successfully parsed the following program at position %t:\n%t\n" (CodeMap.Span.print span) (Ast.print_program program) ; *)
  program, span

(* Le point de départ du compilateur. *)
let _ =

  (* On gère le signal Ctrl + C au cas où pour nettoyer les fichiers*)
  let _ = Sys.signal Sys.sigint (Signal_handle handle_sig) in

  (* On commence par lire le nom du fichier à compiler passé en paramètre. *)
  let n = Array.length Sys.argv in
  if n <= 1 then begin
    (* Pas de fichier... *)
    eprintf "no file provided.\n";
    exit 1
  end else begin
    try
      let outfile = ref "" in
      let srcfile = ref "" in
      if n = 4 then begin
        if Sys.argv.(1) <> "-o" then(
          eprintf "Usage : antsc -o <output> <source file>\n";
          exit 2 ;
        );
        outfile := Sys.argv.(2) ;
        srcfile := Sys.argv.(3) ;
      end else begin
        eprintf "Usage : antsc -o <output> <source file>\n";
        exit 2 ; 
      end;
      (* On compile le fichier. *)
      let program,_ = process_file (!srcfile) in 
      Compil.start_program (program) ([],[]) (!outfile)
    with
    | Lexer.Error (e, span) ->
      eprintf "Lex error: %t: %t\n" (CodeMap.Span.print span) (Lexer.print_error e)
    | Parser.Error (e, span) ->
      eprintf "Parse error: %t: %t\n" (CodeMap.Span.print span) (Parser.print_error e)
    | Failure(str) -> (* Dans le cas d'un crash *)
      let _ = clean_temp () in (* On clean tous les fichiers .temp*)
      let _ = Sys.command "rm -f *.debug" in (* Ici c'est un problème de compil donc le .debug n'est pas intéressant *)
      eprintf " : %s\n" str

  end
