[ActionsPlugin::] Actions Plugin.

A plugin for actions, by which animate characters change the world model.

@ Support for actions is contained in the "actions" plugin, which occupies this
entire chapter. The test group |:actions| may be helpful in trouble-shooting here.

It may be helpful to distinguish these ideas right from the outset:

(*) An "action" (or "explicit action", for the sake of clarity) is a specific
impulse by a person in the model world to effect some change within it: for
example, "Henry taking the brick". Here Henry is the "actor", and the brick is
"the noun". Actions can be "stored" so that they are values in their own
right; thus, a variable could be set to the value "Henry taking the brick",
and this would have kind |K_stored_action|. Inside the compiler they are
represented by //explicit_action// objects.
(*) An "action name" -- not an ideal thing to call it, but traditional -- is the
type of action involved, taken in isolation: for example, "taking". These can
also be values at run-time, they have kind |K_action_name|, and they are
represented in the comoiler by //action_name// objections.
(*) An "action pattern" is a textual description which matches some actions but
not others, and can be vague or specific: for example, "wearing or examining
something". Action patterns become values of the kind |K_description_of_action|.
They can also be aggregated into "named action patterns", which characterise
behaviour; see //action_pattern// and //named_action_pattern//.
(*) A "past action pattern", which can never in any way be a value, is a
description of an action which have happened in the past: for example, "dropped
the hat". These are just a special case of action patterns.

=
void ActionsPlugin::start(void) {
	ActionsNodes::nodes_and_annotations();

	PluginManager::plug(MAKE_SPECIAL_MEANINGS_PLUG, ActionsPlugin::make_special_meanings);
	PluginManager::plug(NEW_BASE_KIND_NOTIFY_PLUG, ARvalues::new_base_kind_notify);
	PluginManager::plug(COMPARE_CONSTANT_PLUG, ARvalues::compare_CONSTANT);
	PluginManager::plug(COMPILE_CONSTANT_PLUG, RTActions::actions_compile_constant);
	PluginManager::plug(COMPILE_CONDITION_PLUG, AConditions::compile_condition);
	PluginManager::plug(CREATION_PLUG, ActionsNodes::creation);
	PluginManager::plug(UNUSUAL_PROPERTY_VALUE_PLUG, ActionsNodes::unusual_property_value_node);
	PluginManager::plug(OFFERED_PROPERTY_PLUG, ActionVariables::actions_offered_property);
	PluginManager::plug(OFFERED_SPECIFICATION_PLUG, ActionsPlugin::actions_offered_specification);
	PluginManager::plug(TYPECHECK_EQUALITY_PLUG, ARvalues::actions_typecheck_equality);
	PluginManager::plug(PRODUCTION_LINE_PLUG, ActionsPlugin::production_line);

	Vocabulary::set_flags(Vocabulary::entry_for_text(L"doing"), ACTION_PARTICIPLE_MC);
	Vocabulary::set_flags(Vocabulary::entry_for_text(L"asking"), ACTION_PARTICIPLE_MC);
}

int ActionsPlugin::production_line(int stage, int debugging, stopwatch_timer *sequence_timer) {
	if (stage == INTER1_CSEQ) {
		BENCH(RTNamedActionPatterns::compile);
		BENCH(RTActions::ActionData);
		BENCH(RTActions::ActionCoding_array);
		BENCH(RTActions::ActionHappened);
		BENCH(RTActions::compile_action_routines);
	}
	return FALSE;
}

@ Though |K_action_name| is very like an enumeration kind, its possible values,
which correspond to //action_name// objects, are not strictly speaking instances
in the Inform world model. (Because they do not have properties: see //Action Variables//
for what they have instead.)

The "waiting" action is sacred, because it is the default value for
|K_action_name| values: waiting is the zero of actions.

= (early code)
action_name *waiting_action = NULL;

@ These are recognised by their English names when defined by the Standard Rules.
(So there is no need to translate this to other languages.)

=
<waiting-action> ::=
	waiting

@ Because //action_name// values are not instances, we cannot recognise them
when instances are created, and instead have to do it directly when this is
called by the function creating them:

=
void ActionsPlugin::notice_new_action_name(action_name *an) {
	if (<waiting-action>(ActionNameNames::tensed(an, IS_TENSE))) {
		if (waiting_action == NULL) waiting_action = an;
	}
	Going::notice_new_action_name(an);
}

action_name *ActionsPlugin::default_action_name(void) {
	if (waiting_action == NULL) internal_error("wait action not ready");
	return waiting_action;
}

@ And because |K_action_name| values have no properties, they cannot store
a "specification" text as one, and have to make their own arrangements:

=
int ActionsPlugin::actions_offered_specification(parse_node *owner, wording W) {
	if (Rvalues::is_CONSTANT_of_kind(owner, K_action_name)) {
		IXActions::actions_set_specification_text(
			ARvalues::to_action_name(owner), Wordings::first_wn(W));
		return TRUE;
	}
	return FALSE;
}

@ The rest of this section is given over to the Preform grammar for dealing
with the special meaning "X is an action...", which creates new action names.
These can be quite complicated:

>> Inserting it into is an action applying to two things.
>> Verifying the story file is an action out of world and applying to nothing.

=
int ActionsPlugin::make_special_meanings(void) {
	SpecialMeanings::declare(ActionsPlugin::new_action_SMF, I"new-action", 2);
	return FALSE;
}

action_name *an_being_parsed = NULL;
int ActionsPlugin::new_action_SMF(int task, parse_node *V, wording *NPs) {
	wording SW = (NPs)?(NPs[0]):EMPTY_WORDING;
	wording OW = (NPs)?(NPs[1]):EMPTY_WORDING;
	switch (task) { /* "Taking something is an action." */
		case ACCEPT_SMFT: @<Check that this validly declares an action@>; break;
		case PASS_1_SMFT: @<Parse the subject and object phrases@>; break;
	}
	return FALSE;
}

@<Check that this validly declares an action@> =
	if (<new-action-sentence-object>(OW)) {
		if (<<r>> == FALSE) return FALSE;
		parse_node *O = <<rp>>;
		<np-unparsed>(SW);
		V->next = <<rp>>;
		V->next->next = O;
		return TRUE;
	}

@ <nounphrase-actionable> here is an awkward necessity, designed to prevent the
regular sentence "The impulse is an action name that varies" from being parsed
as an instance of "... is an action ...", creating a new action.

=
<new-action-sentence-object> ::=
	<indefinite-article> <new-action-sentence-object-unarticled> |  ==> { pass 2 }
	<new-action-sentence-object-unarticled>							==> { pass 1 }

<new-action-sentence-object-unarticled> ::=
	action <nounphrase-actionable> |    ==> { TRUE, RP[1] }
	action								==> @<Issue PM_BadActionDeclaration problem@>

<nounphrase-actionable> ::=
	^<variable-creation-tail>			==> { 0, Diagrams::new_UNPARSED_NOUN(W) }

<variable-creation-tail> ::=
	*** that/which vary/varies |
	*** variable

@<Issue PM_BadActionDeclaration problem@> =
	Problems::Using::assertion_problem(Task::syntax_tree(), _p_(PM_BadActionDeclaration),
		"it is not sufficient to say that something is an 'action'",
		"without giving the necessary details: for example, 'Unclamping "
		"is an action applying to one thing.'");
	==> { FALSE, NULL };

@ Supposing that all that worked, the SP of the sentence is the name for the
new action, and the OP can include a wide range of details about it.

@<Parse the subject and object phrases@> =
	if ((V->next) && (V->next->next))
		if (<action-sentence-subject>(Node::get_text(V->next))) {
			an_being_parsed = <<rp>>;
			an_being_parsed->indexing_data.designers_specification = V->next->next;
			ActionsPlugin::clear_clauses();
			<action-sentence-object>(Node::get_text(V->next->next));
		}

@ The subject noun phrase needs little further parsing -- it's the name of the
action-to-be. A successful match here causes the new //action_name// structure
to be created.

=
<action-sentence-subject> ::=
	<action-name> |  ==> @<Issue PM_ActionAlreadyExists problem@>
	...              ==> { 0, PL::Actions::act_new(W) }

@<Issue PM_ActionAlreadyExists problem@> =
	StandardProblems::sentence_problem(Task::syntax_tree(),
		_p_(PM_ActionAlreadyExists),
		"that seems to be an action already existing",
		"so it cannot be redefined now. If you would like to reconfigure "
		"an action in the standard set - for instance if you prefer "
		"'unlocking' to apply to only one thing, not two - create a new "
		"action for what you need ('keyless unlocking', perhaps) and then "
		"change the grammar to use the new action rather than the old "
		"('Understand \"unlock [something]\" as keyless unlocking.').");
	==> { fail nonterminal };

@ The object NP is a sequence of "action clauses" which can occur in any order,
which are allowed but not required to be delimited as a list, and which can
inconveniently contain the word "and"; not only that, but note that in

>> applying to one thing and one number

the initial text "applying to one thing" would be valid as it stands.

=
<action-sentence-object> ::=
	<action-clauses> |                   ==> { 0, - }
	...                                  ==> @<Issue PM_ActionClauseUnknown problem@>

<action-clauses> ::=
	... |                                         ==> { lookahead }
	<action-clauses> <action-clause-terminated> | ==> { R[2], - }; ActionsPlugin::clause(R[2]);
	<action-clause-terminated>                    ==> { R[1], - }; ActionsPlugin::clause(R[1]);

<action-clause-terminated> ::=
	<action-clause> , and |              ==> { pass 1 }
	<action-clause> and |                ==> { pass 1 }
	<action-clause> , |                  ==> { pass 1 }
	<action-clause>                      ==> { pass 1 }

<action-clause> ::=
	out of world |                       ==> { OOW_ACT_CLAUSE, - }; @<Make out of world@>
	abbreviable |                        ==> { ABBREV_ACT_CLAUSE, - }; @<Make abbreviable@>
	with past participle ... |           ==> { PP_ACT_CLAUSE, - }; @<Give irregular participle@>
	applying to <action-applications> |  ==> { APPLYING_ACT_CLAUSE, - }
	requiring light                      ==> { LIGHT_ACT_CLAUSE, - }; @<Require light@>

<action-applications> ::=
	nothing |
	one <act-req> and one <act-req> |    ==> @<Set kind and access for two@>
	one <act-req> and <act-req> |        ==> @<Set kind and access for two@>
	<act-req> and one <act-req> |        ==> @<Set kind and access for two@>
	<act-req> and <act-req> |            ==> @<Set kind and access for two@>
	nothing or one <act-req> |           ==> @<Set kind and access for an optional one@>
	one <act-req> |                      ==> @<Set kind and access for one@>
	two <act-req>	|                    ==> @<Set kind and access for one, doubling up@>
	<act-req> |                          ==> @<Set kind and access for one@>
	...                                  ==> @<Issue PM_ActionMisapplied problem@>;

<act-req> ::=
	<act-req-inner>                      ==> @<Check action kind@>;

<act-req-inner> ::=
	<action-access> <k-kind> |           ==> { R[1], RP[2] }
	<k-kind>                             ==> { UNRESTRICTED_ACCESS, RP[1] }

<action-access> ::=
	visible |                            ==> { DOESNT_REQUIRE_ACCESS, - }
	touchable |                          ==> { REQUIRES_ACCESS, - }
	carried                              ==> { REQUIRES_POSSESSION, - }

@<Make out of world@> =
	ActionSemantics::make_action_out_of_world(an_being_parsed);

@<Make abbreviable@> =
	ActionNameNames::make_abbreviable(an_being_parsed);

@<Give irregular participle@> =
	ActionNameNames::set_irregular_past(an_being_parsed, GET_RW(<action-clause>, 1));

@<Require light@> =
	ActionSemantics::make_action_require_light(an_being_parsed);

@<Set kind and access for an optional one@> =
	ActionSemantics::give_action_an_optional_noun(an_being_parsed, R[1], RP[1]);

@<Set kind and access for one@> =
	ActionSemantics::give_action_one_noun(an_being_parsed, R[1], RP[1]);

@<Set kind and access for two@> =
	ActionSemantics::give_action_two_nouns(an_being_parsed, R[1], RP[1], R[2], RP[2]);

@<Set kind and access for one, doubling up@> =
	ActionSemantics::give_action_two_nouns(an_being_parsed, R[1], RP[1], R[1], RP[1]);

@<Issue PM_ActionClauseUnknown problem@> =
	StandardProblems::sentence_problem(Task::syntax_tree(),
		_p_(PM_ActionClauseUnknown),
		"the action definition contained text I couldn't follow",
		"and may be too complicated.");

@<Issue PM_ActionMisapplied problem@> =
	StandardProblems::sentence_problem(Task::syntax_tree(),
		_p_(PM_ActionMisapplied),
		"an action can only apply to things or to kinds of value",
		"for instance: 'photographing is an action applying to "
		"one visible thing'.");
	==> { REQUIRES_ACCESS, K_thing };

@<Check action kind@> =
	int A = R[1]; kind *K = RP[1];
	if (Kinds::eq(K, K_thing)) {
		if (A == UNRESTRICTED_ACCESS) A = REQUIRES_ACCESS;
		==> { A, K_object };
	} else if (Kinds::Behaviour::is_subkind_of_object(K)) {
		@<Issue PM_ActionMisapplied problem@>;
	} else if (A != UNRESTRICTED_ACCESS) {
		@<Issue PM_ActionMisapplied problem@>;
	} else {
		==> { A, K };
	}

@ For years this was not erroneous, but you now can't write, say, "X is an
action applying to nothing, applying to nothing, requiring light and applying
to nothing".

@d OOW_ACT_CLAUSE 1
@d PP_ACT_CLAUSE 2
@d APPLYING_ACT_CLAUSE 3
@d LIGHT_ACT_CLAUSE 4
@d ABBREV_ACT_CLAUSE 5

=
int an_clauses_filled[6];
void ActionsPlugin::clear_clauses(void) {
	for (int i=1; i<=5; i++) an_clauses_filled[i] = FALSE;
}
void ActionsPlugin::clause(int N) {
	if (an_clauses_filled[N])
		StandardProblems::sentence_problem(Task::syntax_tree(),
			_p_(PM_ActionClauseRepeated),
			"that seems to repeat a clause",
			"or to specify something twice over.");
	an_clauses_filled[N] = TRUE;
}