[UnderstandLines::] Command Grammar Lines.

A grammar line is a list of tokens to specify a textual pattern.
For example, the Inform source for a grammar line might be "take [something]
out", which is a sequence of three tokens.

@ A grammar line is in turn a sequence of tokens. If it matches, it will
result in 0, 1 or 2 parameters, though only if the command grammar owning
the line is a genuine |CG_IS_COMMAND| command grammar will the case of
2 parameters be possible. (This is for text matching, say, "put X in Y":
the objects X and Y are two parameters resulting.) And in that case (alone),
there will also be a |resulting_action|.

A small amount of disjunction is allowed in a grammar line: for instance,
"look in/inside/into [something]" consists of five tokens, but only three
lexemes, basic units to be matched. (The first is "look", the second
is "one out of in, inside or into", and the third is an object in scope.)
In the following structure we cache the lexeme count since it is fiddly
to calculate, and useful when sorting grammar lines into applicability order.

The individual tokens are stored simply as parse tree nodes of type
|TOKEN_NT|, and are the children of the node |cgl->tokens|, which is why
(for now, anyway) there is no grammar token structure.

@d UNCALCULATED_BONUS -1000000

=
typedef struct cg_line {
	struct cg_line *next_line; /* linked list in creation order */
	struct cg_line *sorted_next_line; /* and in applicability order */

	struct parse_node *where_grammar_specified; /* where found in source */
	int original_text; /* the word number of the double-quoted grammar text... */
	struct parse_node *tokens; /* ...which is parsed into this list of tokens */
	int lexeme_count; /* number of lexemes, or |-1| if not yet counted */
	struct wording understand_when_text; /* only when this condition holds */
	struct pcalc_prop *understand_when_prop; /* and when this condition holds */

	int pluralised; /* |CG_IS_SUBJECT|: refers in the plural */

	struct action_name *resulting_action; /* |CG_IS_COMMAND|: the action */
	int reversed; /* |CG_IS_COMMAND|: the two arguments are in reverse order */
	int mistaken; /* |CG_IS_COMMAND|: is this understood as a mistake? */
	struct wording mistake_response_text; /* if so, reply thus */

	struct determination_type cgl_type;

	int suppress_compilation; /* has been compiled in a single I6 grammar token already? */
	struct cg_line *next_with_action; /* used when indexing actions */
	struct command_grammar *belongs_to_gv; /* similarly, used only in indexing */

	struct inter_name *cond_token_iname; /* for its |Cond_Token_*| routine, if any */
	struct inter_name *mistake_iname; /* for its |Mistake_Token_*| routine, if any */

	int general_sort_bonus; /* temporary values used in grammar line sorting */
	int understanding_sort_bonus;

	CLASS_DEFINITION
} cg_line;

@ =
typedef struct slash_gpr {
	struct parse_node *first_choice;
	struct parse_node *last_choice;
	struct inter_name *sgpr_iname;
	CLASS_DEFINITION
} slash_gpr;

@ =
cg_line *UnderstandLines::new(wording W, action_name *ac,
	parse_node *token_list, int reversed, int pluralised) {
	int wn = Wordings::first_wn(W);
	cg_line *cgl;
	cgl = CREATE(cg_line);
	cgl->original_text = wn;
	cgl->resulting_action = ac;
	cgl->belongs_to_gv = NULL;

	if (ac != NULL) Actions::add_gl(ac, cgl);

	cgl->mistaken = FALSE;
	cgl->mistake_response_text = EMPTY_WORDING;
	cgl->next_with_action = NULL;
	cgl->next_line = NULL;
	cgl->tokens = token_list;
	cgl->where_grammar_specified = current_sentence;
	cgl->cgl_type = DeterminationTypes::new();
	cgl->lexeme_count = -1; /* no count made as yet */
	cgl->reversed = reversed;
	cgl->pluralised = pluralised;
	cgl->understand_when_text = EMPTY_WORDING;
	cgl->understand_when_prop = NULL;
	cgl->suppress_compilation = FALSE;
	cgl->general_sort_bonus = UNCALCULATED_BONUS;
	cgl->understanding_sort_bonus = UNCALCULATED_BONUS;

	cgl->cond_token_iname = NULL;
	cgl->mistake_iname = NULL;

	return cgl;
}

void UnderstandLines::log(cg_line *cgl) {
	LOG("<GL%d:%W>", cgl->allocation_id, Node::get_text(cgl->tokens));
}

void UnderstandLines::set_single_type(cg_line *cgl, parse_node *cgl_value) {
	DeterminationTypes::set_single_term(&(cgl->cgl_type), cgl_value);
}

@h GL lists.
Grammar lines are themselves generally stored in linked lists (belonging,
for instance, to a CG). Here we add a GL to the back of a list.

=
int UnderstandLines::list_length(cg_line *list_head) {
	int c = 0;
	cg_line *posn;
	for (posn = list_head; posn; posn = posn->next_line) c++;
	return c;
}

cg_line *UnderstandLines::list_add(cg_line *list_head, cg_line *new_gl) {
	new_gl->next_line = NULL;
	if (list_head == NULL) list_head = new_gl;
	else {
		cg_line *posn = list_head;
		while (posn->next_line) posn = posn->next_line;
		posn->next_line = new_gl;
	}
	return list_head;
}

cg_line *UnderstandLines::list_remove(cg_line *list_head, action_name *find) {
	cg_line *prev = NULL, *posn = list_head;
	while (posn) {
		if (posn->resulting_action == find) {
			LOGIF(GRAMMAR_CONSTRUCTION, "Removing grammar line: $g\n", posn);
			if (prev) prev->next_line = posn->next_line;
			else list_head = posn->next_line;
		} else {
			prev = posn;
		}
		posn = posn->next_line;
	}
	return list_head;
}

@h Two special forms of grammar lines.
GLs can have either or both of two orthogonal special forms: they can be
mistaken or conditional. (Mistakes only occur in command grammars, but
conditional GLs can occur in any grammar.) GLs of this kind need special
support, in that I6 general parsing routines need to be compiled for them
to use as tokens: here's where that support is provided. The following
step needs to take place before the command grammar (I6 |Verb| directives,
etc.) is compiled because of I6's requirement that all GPRs be defined
as routines prior to the |Verb| directive using them.

=
void UnderstandLines::line_list_compile_condition_tokens(cg_line *list_head) {
	cg_line *cgl;
	for (cgl = list_head; cgl; cgl = cgl->next_line) {
		UnderstandLines::cgl_compile_condition_token_as_needed(cgl);
		UnderstandLines::cgl_compile_mistake_token_as_needed(cgl);
	}
}

@h Conditional lines.
Some grammar lines take effect only when some circumstance holds: most I7
conditions are valid to specify this, with the notation "Understand ... as
... when ...". However, we want to protect new authors from mistakes
like this:

>> Understand "mate" as Fred when asking Fred to do something: ...

where the condition couldn't test anything useful because it's not yet
known what the action will be.

=
<understand-condition> ::=
	<s-non-action-condition> |  ==> { 0, -, <<parse_node:cond>> = RP[1] }
	<s-condition> |             ==> @<Issue PM_WhenAction problem@>
	...                         ==> @<Issue PM_BadWhen problem@>;

@<Issue PM_WhenAction problem@> =
	StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_WhenAction),
		"the condition after 'when' involves the current action",
		"but this can never work, because when Inform is still trying to "
		"understand a command, the current action isn't yet decided on.");

@<Issue PM_BadWhen problem@> =
	StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_BadWhen),
		"the condition after 'when' makes no sense to me",
		"although otherwise this worked - it is only the part after 'when' "
		"which I can't follow.");

@ Such GLs have an "understand when" set, as follows.
They compile preceded by a match-no-text token which matches correctly
if the condition holds and incorrectly if it fails. For instance, for
a command grammar, we might have:

|* Cond_Token_26 'draw' noun -> Draw|

=
void UnderstandLines::set_understand_when(cg_line *cgl, wording W) {
	cgl->understand_when_text = W;
}
void UnderstandLines::set_understand_prop(cg_line *cgl, pcalc_prop *prop) {
	cgl->understand_when_prop = prop;
}
int UnderstandLines::conditional(cg_line *cgl) {
	if ((Wordings::nonempty(cgl->understand_when_text)) || (cgl->understand_when_prop))
		return TRUE;
	return FALSE;
}

void UnderstandLines::cgl_compile_condition_token_as_needed(cg_line *cgl) {
	if (UnderstandLines::conditional(cgl)) {
		current_sentence = cgl->where_grammar_specified;

		package_request *PR = Hierarchy::local_package(COND_TOKENS_HAP);
		cgl->cond_token_iname = Hierarchy::make_iname_in(CONDITIONAL_TOKEN_FN_HL, PR);

		packaging_state save = Routines::begin(cgl->cond_token_iname);

		parse_node *spec = NULL;
		if (Wordings::nonempty(cgl->understand_when_text)) {
			current_sentence = cgl->where_grammar_specified;
			if (<understand-condition>(cgl->understand_when_text)) {
				spec = <<parse_node:cond>>;
				if (Dash::validate_conditional_clause(spec) == FALSE) {
					@<Issue PM_BadWhen problem@>;
					spec = NULL;
				}
			}
		}
		pcalc_prop *prop = cgl->understand_when_prop;

		if ((spec) || (prop)) {
			Produce::inv_primitive(Emit::tree(), IF_BIP);
			Produce::down(Emit::tree());
				if ((spec) && (prop)) {
					Produce::inv_primitive(Emit::tree(), AND_BIP);
					Produce::down(Emit::tree());
				}
				if (spec) Specifications::Compiler::emit_as_val(K_truth_state, spec);
				if (prop) Calculus::Deferrals::emit_test_of_proposition(Rvalues::new_self_object_constant(), prop);
				if ((spec) && (prop)) {
					Produce::up(Emit::tree());
				}
				Produce::code(Emit::tree());
				Produce::down(Emit::tree());
					Produce::inv_primitive(Emit::tree(), RETURN_BIP);
					Produce::down(Emit::tree());
						Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_PREPOSITION_HL));
					Produce::up(Emit::tree());
				Produce::up(Emit::tree());
			Produce::up(Emit::tree());
		}
		Produce::inv_primitive(Emit::tree(), RETURN_BIP);
		Produce::down(Emit::tree());
			Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_FAIL_HL));
		Produce::up(Emit::tree());

		Routines::end(save);
	}
}

void UnderstandLines::cgl_compile_extra_token_for_condition(gpr_kit *gprk, cg_line *cgl,
	int cg_is, inter_symbol *current_label) {
	if (UnderstandLines::conditional(cgl)) {
		if (cgl->cond_token_iname == NULL) internal_error("GL cond token not ready");
		if (cg_is == CG_IS_COMMAND) {
			Emit::array_iname_entry(cgl->cond_token_iname);
		} else {
			Produce::inv_primitive(Emit::tree(), IF_BIP);
			Produce::down(Emit::tree());
				Produce::inv_primitive(Emit::tree(), EQ_BIP);
				Produce::down(Emit::tree());
					Produce::inv_call_iname(Emit::tree(), cgl->cond_token_iname);
					Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_FAIL_HL));
				Produce::up(Emit::tree());
				Produce::code(Emit::tree());
				Produce::down(Emit::tree());
					Produce::inv_primitive(Emit::tree(), JUMP_BIP);
					Produce::down(Emit::tree());
						Produce::lab(Emit::tree(), current_label);
					Produce::up(Emit::tree());
				Produce::up(Emit::tree());
			Produce::up(Emit::tree());
		}
	}
}

@h Mistakes.
These are grammar lines used in command CGs for commands which are accepted
but only in order to print nicely worded rejections. A number of schemes
were tried for this, for instance producing parser errors and setting |pe|
to some high value, but the method now used is for a mistaken line to
produce a successful parse at the I6 level, resulting in the (I6 only)
action |##MistakeAction|. The tricky part is to send information to the
I6 action routine |MistakeActionSub| indicating what the mistake was,
exactly: we do this by including, in the I6 grammar, a token which
matches empty text and returns a "preposition", so that it has no
direct result, but which also sets a special global variable as a
side-effect. Thus a mistaken line "act [thing]" comes out as something
like:

|* Mistake_Token_12 'act' noun -> MistakeAction|

Since the I6 parser accepts the first command which matches, and since
none of this can be recursive, the value of this variable at the end of
I6 parsing is guaranteed to be the one set during the line causing
the mistake.

=
void UnderstandLines::set_mistake(cg_line *cgl, wording MW) {
	cgl->mistaken = TRUE;
	cgl->mistake_response_text = MW;
	if (cgl->mistake_iname == NULL) {
		package_request *PR = Hierarchy::local_package(MISTAKES_HAP);
		cgl->mistake_iname = Hierarchy::make_iname_in(MISTAKE_FN_HL, PR);
	}
}

void UnderstandLines::cgl_compile_mistake_token_as_needed(cg_line *cgl) {
	if (cgl->mistaken) {
		packaging_state save = Routines::begin(cgl->mistake_iname);

		Produce::inv_primitive(Emit::tree(), IF_BIP);
		Produce::down(Emit::tree());
			Produce::inv_primitive(Emit::tree(), NE_BIP);
			Produce::down(Emit::tree());
				Produce::val_iname(Emit::tree(), K_object, Hierarchy::find(ACTOR_HL));
				Produce::val_iname(Emit::tree(), K_object, Hierarchy::find(PLAYER_HL));
			Produce::up(Emit::tree());
			Produce::code(Emit::tree());
			Produce::down(Emit::tree());
				Produce::inv_primitive(Emit::tree(), RETURN_BIP);
				Produce::down(Emit::tree());
					Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_FAIL_HL));
				Produce::up(Emit::tree());
			Produce::up(Emit::tree());
		Produce::up(Emit::tree());

		Produce::inv_primitive(Emit::tree(), STORE_BIP);
		Produce::down(Emit::tree());
			Produce::ref_iname(Emit::tree(), K_number, Hierarchy::find(UNDERSTAND_AS_MISTAKE_NUMBER_HL));
			Produce::val(Emit::tree(), K_number, LITERAL_IVAL, (inter_ti) (100 + cgl->allocation_id));
		Produce::up(Emit::tree());

		Produce::inv_primitive(Emit::tree(), RETURN_BIP);
		Produce::down(Emit::tree());
			Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_PREPOSITION_HL));
		Produce::up(Emit::tree());

		Routines::end(save);
	}
}

void UnderstandLines::cgl_compile_extra_token_for_mistake(cg_line *cgl, int cg_is) {
	if (cgl->mistaken) {
		if (cg_is == CG_IS_COMMAND) {
			Emit::array_iname_entry(cgl->mistake_iname);
		} else
			internal_error("GLs may only be mistaken in command grammar");
	}
}

inter_name *MistakeAction_iname = NULL;

int UnderstandLines::cgl_compile_result_of_mistake(gpr_kit *gprk, cg_line *cgl) {
	if (cgl->mistaken) {
		if (MistakeAction_iname == NULL) internal_error("no MistakeAction yet");
		Emit::array_iname_entry(VERB_DIRECTIVE_RESULT_iname);
		Emit::array_iname_entry(MistakeAction_iname);
		return TRUE;
	}
	return FALSE;
}

void UnderstandLines::MistakeActionSub_routine(void) {
	package_request *MAP = Hierarchy::synoptic_package(SACTIONS_HAP);
	packaging_state save = Routines::begin(Hierarchy::make_iname_in(MISTAKEACTIONSUB_HL, MAP));

	Produce::inv_primitive(Emit::tree(), SWITCH_BIP);
	Produce::down(Emit::tree());
		Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(UNDERSTAND_AS_MISTAKE_NUMBER_HL));
		Produce::code(Emit::tree());
		Produce::down(Emit::tree());
			cg_line *cgl;
			LOOP_OVER(cgl, cg_line)
				if (cgl->mistaken) {
					current_sentence = cgl->where_grammar_specified;
					parse_node *spec = NULL;
					if (Wordings::empty(cgl->mistake_response_text))
						spec = Specifications::new_UNKNOWN(cgl->mistake_response_text);
					else if (<s-value>(cgl->mistake_response_text)) spec = <<rp>>;
					else spec = Specifications::new_UNKNOWN(cgl->mistake_response_text);
					Produce::inv_primitive(Emit::tree(), CASE_BIP);
					Produce::down(Emit::tree());
						Produce::val(Emit::tree(), K_number, LITERAL_IVAL, (inter_ti) (100+cgl->allocation_id));
						Produce::code(Emit::tree());
						Produce::down(Emit::tree());
							Produce::inv_call_iname(Emit::tree(), Hierarchy::find(PARSERERROR_HL));
							Produce::down(Emit::tree());
								Specifications::Compiler::emit_constant_to_kind_as_val(spec, K_text);
							Produce::up(Emit::tree());
						Produce::up(Emit::tree());
					Produce::up(Emit::tree());
				}

			Produce::inv_primitive(Emit::tree(), DEFAULT_BIP);
			Produce::down(Emit::tree());
				Produce::code(Emit::tree());
				Produce::down(Emit::tree());
					Produce::inv_primitive(Emit::tree(), PRINT_BIP);
					Produce::down(Emit::tree());
						Produce::val_text(Emit::tree(), I"I didn't understand that sentence.\n");
					Produce::up(Emit::tree());
					Produce::rtrue(Emit::tree());
				Produce::up(Emit::tree());
			Produce::up(Emit::tree());
		Produce::up(Emit::tree());
	Produce::up(Emit::tree());

	Produce::inv_primitive(Emit::tree(), STORE_BIP);
	Produce::down(Emit::tree());
		Produce::ref_iname(Emit::tree(), K_number, Hierarchy::find(SAY__P_HL));
		Produce::val(Emit::tree(), K_number, LITERAL_IVAL, 1);
	Produce::up(Emit::tree());

	Routines::end(save);
	
	MistakeAction_iname = Hierarchy::make_iname_in(MISTAKEACTION_HL, MAP);
	Emit::named_pseudo_numeric_constant(MistakeAction_iname, K_action_name, 10000);
	Produce::annotate_i(MistakeAction_iname, ACTION_IANN, 1);
	Hierarchy::make_available(Emit::tree(), MistakeAction_iname);
}

@h Single word optimisation.
The grammars used to parse names of objects are normally compiled into
|parse_name| routines. But the I6 parser also uses the |name| property,
and it is advantageous to squeeze as much as possible into |name| and
as little as possible into |parse_name|. The only possible candidates
are grammar lines consisting of single unconditional words, as detected
by the following routine:

=
int UnderstandLines::cgl_contains_single_unconditional_word(cg_line *cgl) {
	parse_node *pn = cgl->tokens->down;
	if ((pn)
		&& (pn->next == NULL)
		&& (Annotations::read_int(pn, slash_class_ANNOT) == 0)
		&& (Annotations::read_int(pn, grammar_token_literal_ANNOT))
		&& (cgl->pluralised == FALSE)
		&& (UnderstandLines::conditional(cgl) == FALSE))
		return Wordings::first_wn(Node::get_text(pn));
	return -1;
}

@ This routine looks through a GL list and marks to suppress all those
GLs consisting only of single unconditional words, which means they
will not be compiled into a |parse_name| routine (or anywhere else).
If the |of| file handle is set, then the words in question are printed
as I6-style dictionary words to it. In practice, this is done when
compiling the |name| property, so that a single scan achieves both
the transfer into |name| and the exclusion from |parse_name| of
affected GLs.

=
cg_line *UnderstandLines::list_take_out_one_word_grammar(cg_line *list_head) {
	cg_line *cgl, *glp;
	for (cgl = list_head, glp = NULL; cgl; cgl = cgl->next_line) {
		int wn = UnderstandLines::cgl_contains_single_unconditional_word(cgl);
		if (wn >= 0) {
			TEMPORARY_TEXT(content)
			WRITE_TO(content, "%w", Lexer::word_text(wn));
			Emit::array_dword_entry(content);
			DISCARD_TEXT(content)
			cgl->suppress_compilation = TRUE;
		} else glp = cgl;
	}
	return list_head;
}

@h Phase I: Slash Grammar.
Slashing is an activity carried out on a per-grammar-line basis, so to slash
a list of GLs we simply slash each GL in turn.

=
void UnderstandLines::line_list_slash(cg_line *cgl_head) {
	cg_line *cgl;
	for (cgl = cgl_head; cgl; cgl = cgl->next_line) {
		UnderstandLines::slash_cg_line(cgl);
	}
}

@ Now the actual slashing process, which does not descend to tokens. We
remove any slashes, and fill in positive numbers in the |qualifier| field
corresponding to non-singleton equivalence classes. Thus "take up/in all
washing/laundry/linen" begins as 10 tokens, three of them forward slashes,
and ends as 7 tokens, with |qualifier| values 0, 1, 1, 0, 2, 2, 2, for
four equivalence classes in turn. Each equivalence class is one lexical
unit, or "lexeme", so the lexeme count is then 4.

In addition, if one of the slashed options is "--", then this means the
empty word, and is removed from the token list; but the first token of the
lexeme is annotated accordingly.

=
void UnderstandLines::slash_cg_line(cg_line *cgl) {
	parse_node *pn;
	int alternatives_group = 0;

	current_sentence = cgl->where_grammar_specified; /* to report problems */

	if (cgl->tokens == NULL)
		internal_error("Null tokens on grammar");

	LOGIF(GRAMMAR_CONSTRUCTION, "Preparing grammar line:\n$T", cgl->tokens);

	for (pn = cgl->tokens->down; pn; pn = pn->next)
		Annotations::write_int(pn, slash_class_ANNOT, 0);

	parse_node *class_start = NULL;
	for (pn = cgl->tokens->down; pn; pn = pn->next) {
		if ((pn->next) &&
			(Wordings::length(Node::get_text(pn->next)) == 1) &&
			(Lexer::word(Wordings::first_wn(Node::get_text(pn->next))) == FORWARDSLASH_V)) { /* slash follows: */
			if (Annotations::read_int(pn, slash_class_ANNOT) == 0) {
				class_start = pn; alternatives_group++; /* start new equiv class */
				Annotations::write_int(class_start, slash_dash_dash_ANNOT, FALSE);
			}

			Annotations::write_int(pn, slash_class_ANNOT,
				alternatives_group); /* make two sides of slash equiv */
			if (pn->next->next)
				Annotations::write_int(pn->next->next, slash_class_ANNOT, alternatives_group);
			if ((pn->next->next) &&
				(Wordings::length(Node::get_text(pn->next->next)) == 1) &&
				(Lexer::word(Wordings::first_wn(Node::get_text(pn->next->next))) == DOUBLEDASH_V)) { /* -- follows: */
				Annotations::write_int(class_start, slash_dash_dash_ANNOT, TRUE);
				pn->next = pn->next->next->next; /* excise slash and dash-dash */
			} else {
				pn->next = pn->next->next; /* excise the slash from the token list */
			}
		}
	}

	LOGIF(GRAMMAR_CONSTRUCTION, "Regrouped as:\n$T", cgl->tokens);

	for (pn = cgl->tokens->down; pn; pn = pn->next)
		if ((Annotations::read_int(pn, slash_class_ANNOT) > 0) &&
			(Annotations::read_int(pn, grammar_token_literal_ANNOT) == FALSE)) {
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_OverAmbitiousSlash),
				"the slash '/' can only be used between single literal words",
				"so 'underneath/under/beneath' is allowed but "
				"'beneath/[florid ways to say under]/under' isn't.");
			break;
		}

	cgl->lexeme_count = 0;

	for (pn = cgl->tokens->down; pn; pn = pn->next) {
		int i = Annotations::read_int(pn, slash_class_ANNOT);
		if (i > 0)
			while ((pn->next) && (Annotations::read_int(pn->next, slash_class_ANNOT) == i))
				pn = pn->next;
		cgl->lexeme_count++;
	}

	LOGIF(GRAMMAR_CONSTRUCTION, "Slashed as:\n$T", cgl->tokens);
}

@h Phase II: Determining Grammar.
Here there is substantial work to do both at the line list level and on
individual lines, and the latter does recurse down to token level too.

The following routine calculates the type of the GL list as the union
of the types of the GLs within it, where union means the narrowest type
such that every GL in the list casts to it. We return null if there
are no GLs in the list, or if the GLs all return null types, or if
an error occurs. (Note that actions in command verb grammars are counted
as null for this purpose, since a grammar used for parsing the player's
commands is not also used to determine a value.)

=
parse_node *UnderstandLines::line_list_determine(cg_line *list_head,
	int depth, int cg_is, command_grammar *cg, int genuinely_verbal) {
	cg_line *cgl;
	int first_flag = TRUE;
	parse_node *spec_union = NULL;
	LOGIF(GRAMMAR_CONSTRUCTION, "Determining GL list for $G\n", cg);

	for (cgl = list_head; cgl; cgl = cgl->next_line) {
		parse_node *spec_of_line =
			UnderstandLines::cgl_determine(cgl, depth, cg_is, cg, genuinely_verbal);

		if (first_flag) { /* initially no expectations: |spec_union| is meaningless */
			spec_union = spec_of_line; /* so we set it to the first result */
			first_flag = FALSE;
			continue;
		}

		if ((spec_union == NULL) && (spec_of_line == NULL))
			continue; /* we expected to find no result, and did: so no problem */

		if ((spec_union) && (spec_of_line)) {
			if (Dash::compatible_with_description(spec_union, spec_of_line) == ALWAYS_MATCH) {
				spec_union = spec_of_line; /* here |spec_of_line| was a wider type */
				continue;
			}
			if (Dash::compatible_with_description(spec_of_line, spec_union) == ALWAYS_MATCH) {
				continue; /* here |spec_union| was already wide enough */
			}
		}

		if ((cg->cg_is == CG_IS_SUBJECT) || (cg->cg_is == CG_IS_VALUE)) continue;

		current_sentence = cgl->where_grammar_specified;
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_MixedOutcome),
			"grammar tokens must have the same outcome whatever the way they are "
			"reached",
			"so writing a line like 'Understand \"within\" or \"next to "
			"[something]\" as \"[my token]\" must be wrong: one way it produces "
			"a thing, the other way it doesn't.");
		spec_union = NULL;
		break; /* to prevent the problem being repeated for the same grammar */
	}

	LOGIF(GRAMMAR_CONSTRUCTION, "Union: $P\n");
	return spec_union;
}

@ There are three tasks here: to determine the type of the GL, to issue a
problem if this type is impossibly large, and to calculate two numerical
quantities used in sorting GLs: the "general sorting bonus" and the
"understanding sorting bonus" (see below).

=
parse_node *UnderstandLines::cgl_determine(cg_line *cgl, int depth,
	int cg_is, command_grammar *cg, int genuinely_verbal) {
	parse_node *spec = NULL;
	parse_node *pn, *pn2;
	int nulls_count, i, nrv, line_length;
	current_sentence = cgl->where_grammar_specified;

	cgl->understanding_sort_bonus = 0;
	cgl->general_sort_bonus = 0;

	nulls_count = 0; /* number of tokens with null results */

	pn = cgl->tokens->down; /* start from first token */
	if ((genuinely_verbal) && (pn)) pn = pn->next; /* unless it's a command verb */

	for (pn2=pn, line_length=0; pn2; pn2 = pn2->next) line_length++;

	int multiples = 0;
	for (i=0; pn; pn = pn->next, i++) {
		if (Node::get_type(pn) != TOKEN_NT)
			internal_error("Bogus node types on grammar");

		int score = 0;
		spec = UnderstandTokens::determine(pn, depth, &score);
		LOGIF(GRAMMAR_CONSTRUCTION, "Result of token <%W> is $P\n", Node::get_text(pn), spec);

		if (spec) {
			if ((Specifications::is_kind_like(spec)) &&
				(K_understanding) &&
				(Kinds::eq(Specifications::to_kind(spec), K_understanding))) { /* "[text]" token */
				int usb_contribution = i - 100;
				if (usb_contribution >= 0) usb_contribution = -1;
				usb_contribution = 100*usb_contribution + (line_length-1-i);
				cgl->understanding_sort_bonus += usb_contribution; /* reduces! */
			}
			int score_multiplier = 1;
			if (DeterminationTypes::get_no_values_described(&(cgl->cgl_type)) == 0) score_multiplier = 10;
			DeterminationTypes::add_term(&(cgl->cgl_type), spec,
				UnderstandTokens::is_multiple(pn));
			cgl->general_sort_bonus += score*score_multiplier;
		} else nulls_count++;

		if (UnderstandTokens::is_multiple(pn)) multiples++;
	}

	if (multiples > 1)
		StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_MultipleMultiples),
			"there can be at most one token in any line which can match "
			"multiple things",
			"so you'll have to remove one of the 'things' tokens and "
			"make it a 'something' instead.");

	nrv = DeterminationTypes::get_no_values_described(&(cgl->cgl_type));
	if (nrv == 0) cgl->general_sort_bonus = 100*nulls_count;
	if (cg_is == CG_IS_COMMAND) spec = NULL;
	else {
		if (nrv < 2) spec = DeterminationTypes::get_single_term(&(cgl->cgl_type));
		else StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_TwoValuedToken),
			"there can be at most one varying part in the definition of a "
			"named token",
			"so 'Understand \"button [a number]\" as \"[button indication]\"' "
			"is allowed but 'Understand \"button [a number] on [something]\" "
			"as \"[button indication]\"' is not.");
	}

	LOGIF(GRAMMAR_CONSTRUCTION,
		"Determined $g: lexeme count %d, sorting bonus %d, arguments %d, "
		"fixed initials %d, type $P\n",
		cgl, cgl->lexeme_count, cgl->general_sort_bonus, nrv,
		cgl->understanding_sort_bonus, spec);

	return spec;
}

@h Phase III: Sort Grammar.
Insertion sort is used to take the linked list of GLs and construct a
separate, sorted version. This is not the controversial part.

=
cg_line *UnderstandLines::list_sort(cg_line *list_head) {
	cg_line *cgl, *gl2, *gl3, *sorted_head;

	if (list_head == NULL) return NULL;

	sorted_head = list_head;
	list_head->sorted_next_line = NULL;

	cgl = list_head;
	while (cgl->next_line) {
		cgl = cgl->next_line;
		gl2 = sorted_head;
		if (UnderstandLines::cg_line_must_precede(cgl, gl2)) {
			sorted_head = cgl;
			cgl->sorted_next_line = gl2;
			continue;
		}
		while (gl2) {
			gl3 = gl2;
			gl2 = gl2->sorted_next_line;
			if (gl2 == NULL) {
				gl3->sorted_next_line = cgl;
				break;
			}
			if (UnderstandLines::cg_line_must_precede(cgl, gl2)) {
				gl3->sorted_next_line = cgl;
				cgl->sorted_next_line = gl2;
				break;
			}
		}
	}
	return sorted_head;
}

@ This is the controversial part: the routine which decides whether one GL
takes precedence (i.e., is parsed earlier than and thus in preference to)
another GL. This algorithm has been hacked many times to try to reach a
position which pleases all designers: something of a lost cause. The
basic motivation is that we need to sort because the various parsers of
I7 grammar (|parse_name| routines, general parsing routines, the I6 command
parser itself) all work by returning the first match achieved. This means
that if grammar line L2 matches a superset of the texts which grammar line
L1 matches, then L1 should be tried first: trying them in the order L2, L1
would mean that L1 could never be matched, which is surely contrary to the
designer's intention. (Compare the rule-sorting algorithm, which has similar
motivation but is entirely distinct, though both use the same primitive
methods for comparing types of single values, i.e., at stages 5b1 and 5c1
below.)

Recall that each GL has a numerical USB (understanding sort bonus) and
GSB (general sort bonus). The following rules are applied in sequence:

(1) Higher USBs beat lower USBs.

(2a) For sorting GLs in player-command grammar, shorter lines beat longer
lines, where length is calculated as the lexeme count.

(2b) For sorting all other GLs, longer lines beat shorter lines.

(3) Mistaken commands beat unmistaken commands.

(4) Higher GSBs beat lower GSBs.

(5a) Fewer resulting values beat more resulting values.

(5b1) A narrower first result type beats a wider first result type, if
there is a first result.

(5b2) A multiples-disallowed first result type beats a multiples-allowed
first result type, if there is a first result.

(5c1) A narrower second result type beats a wider second result type, if
there is a second result.

(5c2) A multiples-disallowed second result type beats a multiples-allowed
second result type, if there is a second result.

(6) Conditional lines (with a "when" proviso, that is) beat
unconditional lines.

(7) The grammar line defined earlier beats the one defined later.

Rule 1 is intended to resolve awkward ambiguities involved with command
grammar which includes "[text]" tokens. Each such token subtracts 10000 from
the USB of a line but adds back 100 times the token position (which is at least
0 and which we can safely suppose is less than 99: we truncate just in case
so that every |"[text]"| certainly makes a negative contribution of at least
$-100$) and then subtracts off the number of tokens left on the line.

Because a high USB gets priority, and "[text]" tokens make a negative
contribution, the effect is to relegate lines containing "[text]" tokens
to the bottom of the list -- which is good because "[text]" voraciously
eats up words, matching more or less anything, so that any remotely
specific case ought to be tried first. The effect of the curious addition
back in of the token position is that later-placed "[text]" tokens are
tried before earlier-placed ones. Thus |"read chapter [text]"| has a USB
of $-98$, and takes precedence over |"read [text]"| with a USB of $-99$,
but both are beaten by just |"read [something]"| with a USB of 0.
The effect of the subtraction back of the number of tokens remaining
is to ensure that |"read [token] backwards"| takes priority over
|"read [token]"|.

The voracity of |"[text]"|, and its tendency to block out all other
possibilities unless restrained, has to be addressed by this lexically
based numerical calculation because it works in a lexical sort of way:
playing with the types system to prefer |DESCRIPTION/UNDERSTANDING|
over, say, |VALUE/OBJECT| would not be sufficient.

The most surprising point here is the asymmetry in rule 2, which basically
says that when parsing commands typed at the keyboard, shorter beats longer,
whereas in all other settings longer beats shorter. This arises because the
I6 parser, at run time, traditionally works that way: I6 command grammars
are normally stored with short forms first and long forms afterward. The
I6 parser can afford to do this because it is matching text of known length:
if parsing TAKE FROG FROM AQUARIUM, it will try TAKE FROG first but is able
to reject this as not matching the whole text. In other parsing settings,
we are trying to make a maximum-length match against a potentially infinite
stream of words, and it is therefore important to try to match WATERY
CASCADE EFFECT before WATERY CASCADE when looking at text like WATERY
CASCADE EFFECT IMPRESSES PEOPLE, given that the simplistic parsers we
compile generally return the first match found.

Rule 3, that mistakes beat non-mistakes, was in fact rule 1 during 2006: it
seemed logical that since mistakes were exceptional cases, they would be
better checked earlier before moving on to general cases. However, an
example provided by Eric Eve showed that although this was logically correct,
the I6 parser would try to auto-complete lengthy mistakes and thus fail to
check subsequent commands. For this reason, |"look behind [something]"|
as a mistake needs to be checked after |"look"|, or else the I6 parser
will respond to the command LOOK by replying "What do you want to look
behind?" -- and then saying that you are mistaken.

Rule 4 is intended as a lexeme-based tiebreaker. We only get here if there
are the same number of lexemes in the two GLs being compared. Each is
given a GSB score as follows: a literal lexeme, which produces no result,
such as |"draw"| or |"in/inside/within"|, scores 100; all other lexemes
score as follows:

-- |"[things inside]"| scores a GSB of 10 as the first parameter, 1 as the second;

-- |"[things preferably held]"| similarly scores a GSB of 20 or 2;

-- |"[other things]"| similarly scores a GSB of 20 or 2;

-- |"[something preferably held]"| similarly scores a GSB of 30 or 3;

-- any token giving a logical description of some class of objects, such as
|"[open container]"|, similarly scores a GSB of 50 or 5;

-- and any remaining token (for instance, one matching a number or some other
kind of value) scores a GSB of 0.

Literals score highly because they are structural, and differentiate
cases: under the superset rule, |"look up [thing]"| must be parsed before
|"look [direction] [thing]"|, and it is only the number of literals which
differentiates these cases. If two lines have an equal number of literals,
we now look at the first resultant lexeme. Here we find that a lexeme which
specifies an object (with a GSB of at least 10/1) beats a lexeme which only
specifies a value. Thus the same text will be parsed against objects in
preference to values, which is sensible since there are generally few
objects available to the player and they are generally likely to be the
things being referred to. Among possible object descriptions, the very
general catch-all special cases above are given lower GSB scores than
more specific ones, to enable the more specific cases to go first.

Rule 5a is unlikely to have much effect: it is likely to be rare for GL
lists to contain GLs mixing different numbers of results. But Rule 5b1
is very significant: it causes |"draw [animal]"| to have precedence over
|"draw [thing]"|, for instance. Rule 5b2 ensures that |"draw [thing]"|
takes precedence over |"draw [things]"|, which may be useful to handle
multiple and single objects differently.

The motivation for rule 6 is similar to the case of "when" clauses for
rules in rulebooks: it ensures that a match of |"draw [thing]"| when some
condition holds beats a match of |"draw [thing]"| at any time, and this is
necessary under the strict superset principle.

To get to rule 7 looks difficult, given the number of things about the
grammar lines which must match up -- same USB, GSB, number of lexemes,
number of resulting types, equivalent resulting types, same conditional
status -- but in fact it isn't all that uncommon. Equivalent pairs produced
by the Standard Rules include:

|"get off [something]"| and |"get in/into/on/onto [something]"|

|"turn on [something]"| and |"turn [something] on"|

Only the second of these pairs leads to ambiguity, and even then only if
an object has a name like ON VISION ON -- perhaps a book about the antique
BBC children's television programme "Vision On" -- so that the command
TURN ON VISION ON would match both of the alternative GLs.

=
int UnderstandLines::cg_line_must_precede(cg_line *L1, cg_line *L2) {
	int cs, a, b;

	if ((L1 == NULL) || (L2 == NULL))
		internal_error("tried to sort null GLs");
	if ((L1->lexeme_count == -1) || (L2->lexeme_count == -1))
		internal_error("tried to sort unslashed GLs");
	if ((L1->general_sort_bonus == UNCALCULATED_BONUS) ||
		(L2->general_sort_bonus == UNCALCULATED_BONUS))
		internal_error("tried to sort uncalculated GLs");
	if (L1 == L2) return FALSE;

	a = FALSE; if ((L1->resulting_action) || (L1->mistaken)) a = TRUE;
	b = FALSE; if ((L2->resulting_action) || (L2->mistaken)) b = TRUE;
	if (a != b) {
		LOG("L1 = $g\nL2 = $g\n", L1, L2);
		internal_error("tried to sort on incomparable GLs");
	}

	if (L1->understanding_sort_bonus > L2->understanding_sort_bonus) return TRUE;
	if (L1->understanding_sort_bonus < L2->understanding_sort_bonus) return FALSE;

	if (a) { /* command grammar: shorter beats longer */
		if (L1->lexeme_count < L2->lexeme_count) return TRUE;
		if (L1->lexeme_count > L2->lexeme_count) return FALSE;
	} else { /* all other grammars: longer beats shorter */
		if (L1->lexeme_count < L2->lexeme_count) return FALSE;
		if (L1->lexeme_count > L2->lexeme_count) return TRUE;
	}

	if ((L1->mistaken) && (L2->mistaken == FALSE)) return TRUE;
	if ((L1->mistaken == FALSE) && (L2->mistaken)) return FALSE;

	if (L1->general_sort_bonus > L2->general_sort_bonus) return TRUE;
	if (L1->general_sort_bonus < L2->general_sort_bonus) return FALSE;

	cs = DeterminationTypes::must_precede(&(L1->cgl_type), &(L2->cgl_type));
	if (cs != NOT_APPLICABLE) return cs;

	if ((UnderstandLines::conditional(L1)) && (UnderstandLines::conditional(L2) == FALSE)) return TRUE;
	if ((UnderstandLines::conditional(L1) == FALSE) && (UnderstandLines::conditional(L2))) return FALSE;

	return FALSE;
}

@h Phase IV: Compile Grammar.
At this level we compile the list of GLs in sorted order: this is what the
sorting was all for. In certain cases, we skip any GLs marked as "one word":
these are cases arising from, e.g., "Understand "frog" as the toad.",
where we noticed that the GL was a single word and included it in the |name|
property instead. This is faster and more flexible, besides writing tidier
code.

The need for this is not immediately obvious. After all, shouldn't we have
simply deleted the GL in the first place, rather than leaving it in but
marking it? The answer is no, because of the way inheritance works: values
of the |name| property accumulate from class to instance in I6, since
|name| is additive, but grammar doesn't.

=
void UnderstandLines::sorted_line_list_compile(gpr_kit *gprk, cg_line *list_head,
	int cg_is, command_grammar *cg, int genuinely_verbal) {
	for (cg_line *cgl = list_head; cgl; cgl = cgl->sorted_next_line)
		if (cgl->suppress_compilation == FALSE)
			UnderstandLines::compile_cg_line(gprk, cgl, cg_is, cg, genuinely_verbal);
}

@ The following apparently global variables are used to provide a persistent
state for the routine below, but are not accessed elsewhere. The label
counter is reset at the start of each CG's compilation, though this is a
purely cosmetic effect.

=
int current_grammar_block = 0;
int current_label = 1;
int GV_IS_VALUE_instance_mode = FALSE;

void UnderstandLines::reset_labels(void) {
	current_label = 1;
}

@ As fancy as the following routine may look, it contains very little.
What complexity there is comes from the fact that command CGs are compiled
very differently to all others (most grammars are compiled in "code mode",
generating procedural I6 statements, but command CGs are compiled to lines
in |Verb| directives) and that GLs resulting in actions (i.e., GLs in
command CGs) have not yet been type-checked, whereas all others have.

=
void UnderstandLines::compile_cg_line(gpr_kit *gprk, cg_line *cgl, int cg_is, command_grammar *cg,
	int genuinely_verbal) {
	parse_node *pn;
	int i;
	int token_values;
	kind *token_value_kinds[2];
	int code_mode, consult_mode;

	LOGIF(GRAMMAR, "Compiling grammar line: $g\n", cgl);

	current_sentence = cgl->where_grammar_specified;

	if (cg_is == CG_IS_COMMAND) code_mode = FALSE; else code_mode = TRUE;
	if (cg_is == CG_IS_CONSULT) consult_mode = TRUE; else consult_mode = FALSE;

	switch (cg_is) {
		case CG_IS_COMMAND:
		case CG_IS_TOKEN:
		case CG_IS_CONSULT:
		case CG_IS_SUBJECT:
		case CG_IS_VALUE:
		case CG_IS_PROPERTY_NAME:
			break;
		default: internal_error("tried to compile unknown CG type");
	}

	current_grammar_block++;
	token_values = 0;
	for (i=0; i<2; i++) token_value_kinds[i] = NULL;

	if (code_mode == FALSE) Emit::array_iname_entry(VERB_DIRECTIVE_DIVIDER_iname);

	inter_symbol *fail_label = NULL;

	if (gprk) {
		TEMPORARY_TEXT(L)
		WRITE_TO(L, ".Fail_%d", current_label);
		fail_label = Produce::reserve_label(Emit::tree(), L);
		DISCARD_TEXT(L)
	}

	UnderstandLines::cgl_compile_extra_token_for_condition(gprk, cgl, cg_is, fail_label);
	UnderstandLines::cgl_compile_extra_token_for_mistake(cgl, cg_is);

	pn = cgl->tokens->down;
	if ((genuinely_verbal) && (pn)) {
		if (Annotations::read_int(pn, slash_class_ANNOT) != 0) {
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_SlashedCommand),
				"at present you're not allowed to use a / between command "
				"words at the start of a line",
				"so 'put/interpose/insert [something]' is out.");
			return;
		}
		pn = pn->next; /* skip command word: the |Verb| header contains it already */
	}

	if ((cg_is == CG_IS_VALUE) && (GV_IS_VALUE_instance_mode)) {
		Produce::inv_primitive(Emit::tree(), IF_BIP);
		Produce::down(Emit::tree());
			Produce::inv_primitive(Emit::tree(), EQ_BIP);
			Produce::down(Emit::tree());
				Produce::val_symbol(Emit::tree(), K_value, gprk->instance_s);
				RTCommandGrammars::emit_determination_type(&(cgl->cgl_type));
			Produce::up(Emit::tree());
			Produce::code(Emit::tree());
			Produce::down(Emit::tree());
	}

	parse_node *pn_from = pn, *pn_to = pn_from;
	for (; pn; pn = pn->next) pn_to = pn;

	UnderstandLines::compile_token_line(gprk, code_mode, pn_from, pn_to, cg_is, consult_mode, &token_values, token_value_kinds, NULL, fail_label);

	switch (cg_is) {
		case CG_IS_COMMAND:
			if (UnderstandLines::cgl_compile_result_of_mistake(gprk, cgl)) break;
			Emit::array_iname_entry(VERB_DIRECTIVE_RESULT_iname);
			Emit::array_action_entry(cgl->resulting_action);

			if (cgl->reversed) {
				if (token_values < 2) {
					StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_CantReverseOne),
						"you can't use a 'reversed' action when you supply fewer "
						"than two values for it to apply to",
						"since reversal is the process of exchanging them.");
					return;
				}
				kind *swap = token_value_kinds[0];
				token_value_kinds[0] = token_value_kinds[1];
				token_value_kinds[1] = swap;
				Emit::array_iname_entry(VERB_DIRECTIVE_REVERSE_iname);
			}

			ActionSemantics::check_valid_application(cgl->resulting_action, token_values,
				token_value_kinds);
			break;
		case CG_IS_PROPERTY_NAME:
		case CG_IS_TOKEN:
			Produce::inv_primitive(Emit::tree(), RETURN_BIP);
			Produce::down(Emit::tree());
				Produce::val_symbol(Emit::tree(), K_value, gprk->rv_s);
			Produce::up(Emit::tree());
			Produce::place_label(Emit::tree(), fail_label);
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_symbol(Emit::tree(), K_value, gprk->rv_s);
				Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_PREPOSITION_HL));
			Produce::up(Emit::tree());
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
				Produce::val_symbol(Emit::tree(), K_value, gprk->original_wn_s);
			Produce::up(Emit::tree());
			break;
		case CG_IS_CONSULT:
			Produce::inv_primitive(Emit::tree(), IF_BIP);
			Produce::down(Emit::tree());
				Produce::inv_primitive(Emit::tree(), OR_BIP);
				Produce::down(Emit::tree());
					Produce::inv_primitive(Emit::tree(), EQ_BIP);
					Produce::down(Emit::tree());
						Produce::val_symbol(Emit::tree(), K_value, gprk->range_words_s);
						Produce::val(Emit::tree(), K_number, LITERAL_IVAL, 0);
					Produce::up(Emit::tree());
					Produce::inv_primitive(Emit::tree(), EQ_BIP);
					Produce::down(Emit::tree());
						Produce::inv_primitive(Emit::tree(), MINUS_BIP);
						Produce::down(Emit::tree());
							Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
							Produce::val_symbol(Emit::tree(), K_value, gprk->range_from_s);
						Produce::up(Emit::tree());
						Produce::val_symbol(Emit::tree(), K_value, gprk->range_words_s);
					Produce::up(Emit::tree());
				Produce::up(Emit::tree());
				Produce::code(Emit::tree());
				Produce::down(Emit::tree());
					Produce::inv_primitive(Emit::tree(), RETURN_BIP);
					Produce::down(Emit::tree());
						Produce::val_symbol(Emit::tree(), K_value, gprk->rv_s);
					Produce::up(Emit::tree());
				Produce::up(Emit::tree());
			Produce::up(Emit::tree());

			Produce::place_label(Emit::tree(), fail_label);
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_symbol(Emit::tree(), K_value, gprk->rv_s);
				Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_PREPOSITION_HL));
			Produce::up(Emit::tree());
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
				Produce::val_symbol(Emit::tree(), K_value, gprk->original_wn_s);
			Produce::up(Emit::tree());
			break;
		case CG_IS_SUBJECT:
			UnderstandGeneralTokens::after_gl_failed(gprk, fail_label, cgl->pluralised);
			break;
		case CG_IS_VALUE:
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(PARSED_NUMBER_HL));
				RTCommandGrammars::emit_determination_type(&(cgl->cgl_type));
			Produce::up(Emit::tree());
			Produce::inv_primitive(Emit::tree(), RETURN_BIP);
			Produce::down(Emit::tree());
				Produce::val_iname(Emit::tree(), K_object, Hierarchy::find(GPR_NUMBER_HL));
			Produce::up(Emit::tree());
			Produce::place_label(Emit::tree(), fail_label);
			Produce::inv_primitive(Emit::tree(), STORE_BIP);
			Produce::down(Emit::tree());
				Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
				Produce::val_symbol(Emit::tree(), K_value, gprk->original_wn_s);
			Produce::up(Emit::tree());
			break;
	}

	if ((cg_is == CG_IS_VALUE) && (GV_IS_VALUE_instance_mode)) {
			Produce::up(Emit::tree());
		Produce::up(Emit::tree());
	}

	current_label++;
}

void UnderstandLines::compile_token_line(gpr_kit *gprk, int code_mode, parse_node *pn, parse_node *pn_to, int cg_is, int consult_mode,
	int *token_values, kind **token_value_kinds, inter_symbol *group_wn_s, inter_symbol *fail_label) {
	int lexeme_equivalence_class = 0;
	int alternative_number = 0;
	int empty_text_allowed_in_lexeme = FALSE;

	inter_symbol *next_reserved_label = NULL;
	inter_symbol *eog_reserved_label = NULL;
	for (; pn; pn = pn->next) {
		if ((UnderstandTokens::is_text(pn)) && (pn->next) &&
			(UnderstandTokens::is_literal(pn->next) == FALSE)) {
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_TextFollowedBy),
				"a '[text]' token must either match the end of some text, or "
				"be followed by definitely known wording",
				"since otherwise the run-time parser isn't good enough to "
				"make sense of things.");
		}

		if ((Node::get_grammar_token_relation(pn)) && (cg_is != CG_IS_SUBJECT)) {
			if (problem_count == 0)
			StandardProblems::sentence_problem(Task::syntax_tree(), _p_(PM_GrammarObjectlessRelation),
				"a grammar token in an 'Understand...' can only be based "
				"on a relation if it is to understand the name of a room or thing",
				"since otherwise there is nothing for the relation to be with.");
			continue;
		}

		int first_token_in_lexeme = FALSE, last_token_in_lexeme = FALSE;

		if (Annotations::read_int(pn, slash_class_ANNOT) != 0) { /* in a multi-token lexeme */
			if ((pn->next == NULL) ||
				(Annotations::read_int(pn->next, slash_class_ANNOT) !=
					Annotations::read_int(pn, slash_class_ANNOT)))
				last_token_in_lexeme = TRUE;
			if (Annotations::read_int(pn, slash_class_ANNOT) != lexeme_equivalence_class) {
				first_token_in_lexeme = TRUE;
				empty_text_allowed_in_lexeme =
					Annotations::read_int(pn, slash_dash_dash_ANNOT);
			}
			lexeme_equivalence_class = Annotations::read_int(pn, slash_class_ANNOT);
			if (first_token_in_lexeme) alternative_number = 1;
			else alternative_number++;
		} else { /* in a single-token lexeme */
			lexeme_equivalence_class = 0;
			first_token_in_lexeme = TRUE;
			last_token_in_lexeme = TRUE;
			empty_text_allowed_in_lexeme = FALSE;
			alternative_number = 1;
		}

		inter_symbol *jump_on_fail = fail_label;

		if (lexeme_equivalence_class > 0) {
			if (code_mode) {
				if (first_token_in_lexeme) {
					Produce::inv_primitive(Emit::tree(), STORE_BIP);
					Produce::down(Emit::tree());
						Produce::ref_symbol(Emit::tree(), K_value, gprk->group_wn_s);
						Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
					Produce::up(Emit::tree());
				}
				if (next_reserved_label) Produce::place_label(Emit::tree(), next_reserved_label);
				TEMPORARY_TEXT(L)
				WRITE_TO(L, ".group_%d_%d_%d", current_grammar_block, lexeme_equivalence_class, alternative_number+1);
				next_reserved_label = Produce::reserve_label(Emit::tree(), L);
				DISCARD_TEXT(L)

				Produce::inv_primitive(Emit::tree(), STORE_BIP);
				Produce::down(Emit::tree());
					Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
					Produce::val_symbol(Emit::tree(), K_value, gprk->group_wn_s);
				Produce::up(Emit::tree());

				if ((last_token_in_lexeme == FALSE) || (empty_text_allowed_in_lexeme)) {
					jump_on_fail = next_reserved_label;
				}
			}
		}

		if ((empty_text_allowed_in_lexeme) && (code_mode == FALSE)) {
			slash_gpr *sgpr = CREATE(slash_gpr);
			sgpr->first_choice = pn;
			while ((pn->next) &&
					(Annotations::read_int(pn->next, slash_class_ANNOT) ==
					Annotations::read_int(pn, slash_class_ANNOT))) pn = pn->next;
			sgpr->last_choice = pn;
			package_request *PR = Hierarchy::local_package(SLASH_TOKENS_HAP);
			sgpr->sgpr_iname = Hierarchy::make_iname_in(SLASH_FN_HL, PR);
			Emit::array_iname_entry(sgpr->sgpr_iname);
			last_token_in_lexeme = TRUE;
		} else {
			kind *grammar_token_kind =
				UnderstandTokens::compile(gprk, pn, code_mode, jump_on_fail, consult_mode);
			if (grammar_token_kind) {
				if (token_values) {
					if (*token_values == 2) {
						internal_error(
							"There can be at most two value-producing tokens and this "
							"should have been detected earlier.");
						return;
					}
					token_value_kinds[(*token_values)++] = grammar_token_kind;
				}
			}
		}

		if (lexeme_equivalence_class > 0) {
			if (code_mode) {
				if (last_token_in_lexeme) {
					if (empty_text_allowed_in_lexeme) {
						@<Jump to end of group@>;
						if (next_reserved_label)
							Produce::place_label(Emit::tree(), next_reserved_label);
						next_reserved_label = NULL;
						Produce::inv_primitive(Emit::tree(), STORE_BIP);
						Produce::down(Emit::tree());
							Produce::ref_iname(Emit::tree(), K_value, Hierarchy::find(WN_HL));
							Produce::val_symbol(Emit::tree(), K_value, gprk->group_wn_s);
						Produce::up(Emit::tree());
					}
					if (eog_reserved_label) Produce::place_label(Emit::tree(), eog_reserved_label);
					eog_reserved_label = NULL;
				} else {
					@<Jump to end of group@>;
				}
			} else {
				if (last_token_in_lexeme == FALSE) Emit::array_iname_entry(VERB_DIRECTIVE_SLASH_iname);
			}
		}

		if (pn == pn_to) break;
	}
}

@<Jump to end of group@> =
	if (eog_reserved_label == NULL) {
		TEMPORARY_TEXT(L)
		WRITE_TO(L, ".group_%d_%d_end",
			current_grammar_block, lexeme_equivalence_class);
		eog_reserved_label = Produce::reserve_label(Emit::tree(), L);
	}
	Produce::inv_primitive(Emit::tree(), JUMP_BIP);
	Produce::down(Emit::tree());
		Produce::lab(Emit::tree(), eog_reserved_label);
	Produce::up(Emit::tree());

@ =
void UnderstandLines::compile_slash_gprs(void) {
	slash_gpr *sgpr;
	LOOP_OVER(sgpr, slash_gpr) {
		packaging_state save = Routines::begin(sgpr->sgpr_iname);
		gpr_kit gprk = UnderstandValueTokens::new_kit();
		UnderstandValueTokens::add_original(&gprk);
		UnderstandValueTokens::add_standard_set(&gprk);

		UnderstandLines::compile_token_line(&gprk, TRUE, sgpr->first_choice, sgpr->last_choice, CG_IS_TOKEN, FALSE, NULL, NULL, gprk.group_wn_s, NULL);
		Produce::inv_primitive(Emit::tree(), RETURN_BIP);
		Produce::down(Emit::tree());
			Produce::val_iname(Emit::tree(), K_value, Hierarchy::find(GPR_PREPOSITION_HL));
		Produce::up(Emit::tree());
		Routines::end(save);
	}
}

@h Indexing by grammar.
This is the more obvious form of indexing: we show the grammar lines which
make up an individual GL. (For instance, this is used in the Actions index
to show the grammar for an individual command word, by calling the routine
below for that command word's CG.) Such an index list is done in sorted
order, so that the order of appearance in the index corresponds to the
order of parsing -- this is what the reader of the index is interested in.

=
void UnderstandLines::sorted_list_index_normal(OUTPUT_STREAM,
	cg_line *list_head, text_stream *headword) {
	cg_line *cgl;
	for (cgl = list_head; cgl; cgl = cgl->sorted_next_line)
		UnderstandLines::cgl_index_normal(OUT, cgl, headword);
}

void UnderstandLines::cgl_index_normal(OUTPUT_STREAM, cg_line *cgl, text_stream *headword) {
	action_name *an = cgl->resulting_action;
	if (an == NULL) return;
	Index::anchor(OUT, headword);
	if (ActionSemantics::is_out_of_world(an))
		HTML::begin_colour(OUT, I"800000");
	WRITE("&quot;");
	CommandsIndex::verb_definition(OUT, Lexer::word_text(cgl->original_text),
		headword, EMPTY_WORDING);
	WRITE("&quot;");
	Index::link(OUT, cgl->original_text);
	WRITE(" - <i>%+W", ActionNameNames::tensed(an, IS_TENSE));
	Index::detail_link(OUT, "A", an->allocation_id, TRUE);
	if (cgl->reversed) WRITE(" (reversed)");
	WRITE("</i>");
	if (ActionSemantics::is_out_of_world(an))
		HTML::end_colour(OUT);
	HTML_TAG("br");
}

@h Indexing by action.
Grammar lines are typically indexed twice: the other time is when all
grammar lines belonging to a given action are tabulated. Special linked
lists are kept for this purpose, and this is where we unravel them and
print to the index. The question of sorted vs unsorted is meaningless
here, since the GLs appearing in such a list will typically belong to
several different CGs. (As it happens, they appear in order of creation,
i.e., in source text order.)

Tiresomely, all of this means that we need to store "uphill" pointers
in GLs: back up to the CGs that own them. The following routine does
this for a whole list of GLs:

=
void UnderstandLines::list_assert_ownership(cg_line *list_head, command_grammar *cg) {
	cg_line *cgl;
	for (cgl = list_head; cgl; cgl = cgl->next_line)
		cgl->belongs_to_gv = cg;
}

@ And this routine accumulates the per-action lists of GLs:

=
void UnderstandLines::list_with_action_add(cg_line *list_head, cg_line *cgl) {
	if (list_head == NULL) internal_error("tried to add to null action list");
	while (list_head->next_with_action)
		list_head = list_head->next_with_action;
	list_head->next_with_action = cgl;
}

@ Finally, here we index an action list of GLs, each getting a line in
the HTML index.

=
int UnderstandLines::index_list_with_action(OUTPUT_STREAM, cg_line *cgl) {
	int said_something = FALSE;
	while (cgl != NULL) {
		if (cgl->belongs_to_gv) {
			wording VW = CommandGrammars::get_verb_text(cgl->belongs_to_gv);
			TEMPORARY_TEXT(trueverb)
			if (Wordings::nonempty(VW))
				WRITE_TO(trueverb, "%W", Wordings::one_word(Wordings::first_wn(VW)));
			HTML::open_indented_p(OUT, 2, "hanging");
			WRITE("&quot;");
			CommandsIndex::verb_definition(OUT,
				Lexer::word_text(cgl->original_text), trueverb, VW);
			WRITE("&quot;");
			Index::link(OUT, cgl->original_text);
			if (cgl->reversed) WRITE(" <i>reversed</i>");
			HTML_CLOSE("p");
			said_something = TRUE;
			DISCARD_TEXT(trueverb)
		}
		cgl = cgl->next_with_action;
	}
	return said_something;
}

@ And the same, but more simply:

=
void UnderstandLines::index_list_for_token(OUTPUT_STREAM, cg_line *cgl) {
	int k = 0;
	while (cgl != NULL) {
		if (cgl->belongs_to_gv) {
			wording VW = CommandGrammars::get_verb_text(cgl->belongs_to_gv);
			TEMPORARY_TEXT(trueverb)
			if (Wordings::nonempty(VW))
				WRITE_TO(trueverb, "%W", Wordings::one_word(Wordings::first_wn(VW)));
			HTML::open_indented_p(OUT, 2, "hanging");
			if (k++ == 0) WRITE("="); else WRITE("or");
			WRITE(" &quot;");
			CommandsIndex::verb_definition(OUT,
				Lexer::word_text(cgl->original_text), trueverb, EMPTY_WORDING);
			WRITE("&quot;");
			Index::link(OUT, cgl->original_text);
			if (cgl->reversed) WRITE(" <i>reversed</i>");
			HTML_CLOSE("p");
			DISCARD_TEXT(trueverb)
		}
		cgl = cgl->sorted_next_line;
	}
}