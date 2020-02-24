[Projects::] Project Services.

An Inform 7 project.

@ =
typedef struct inform_project {
	struct inbuild_copy *as_copy;
	struct semantic_version_number version;
	struct linked_list *source_vertices; /* of |build_vertex| */
	int assumed_to_be_parser_IF;
	struct linked_list *kits_to_include; /* of |inform_kit| */
	struct inform_language *language_of_play;
	struct inform_language *language_of_syntax;
	struct inform_language *language_of_index;
	struct build_vertex *chosen_build_target;
	int next_resource_number;
	MEMORY_MANAGEMENT
} inform_project;

inform_project *Projects::new_ip(text_stream *name, filename *F, pathname *P) {
	inform_project *project = CREATE(inform_project);
	project->as_copy = NULL;
	project->version = VersionNumbers::null();
	project->source_vertices = NEW_LINKED_LIST(build_vertex);
	project->kits_to_include = NEW_LINKED_LIST(inform_kit);
	project->assumed_to_be_parser_IF = TRUE;
	project->language_of_play = NULL;
	project->language_of_syntax = NULL;
	project->language_of_index = NULL;
	project->next_resource_number = 3;
	project->chosen_build_target = NULL;
	return project;
}

void Projects::set_language_of_play(inform_project *proj, inform_language *L) {
	if (proj == NULL) internal_error("no project");
	proj->language_of_play = L;
}
inform_language *Projects::get_language_of_play(inform_project *proj) {
	if (proj == NULL) return NULL;
	return proj->language_of_play;
}

void Projects::set_language_of_index(inform_project *proj, inform_language *L) {
	if (proj == NULL) internal_error("no project");
	proj->language_of_index = L;
}
inform_language *Projects::get_language_of_index(inform_project *proj) {
	if (proj == NULL) return NULL;
	return proj->language_of_index;
}

void Projects::set_language_of_syntax(inform_project *proj, inform_language *L) {
	if (proj == NULL) internal_error("no project");
	proj->language_of_syntax = L;
	#ifdef CORE_MODULE
	English_language = L;
	#endif
}
inform_language *Projects::get_language_of_syntax(inform_project *proj) {
	if (proj == NULL) return NULL;
	return proj->language_of_syntax;
}

void Projects::not_necessarily_parser_IF(inform_project *project) {
	project->assumed_to_be_parser_IF = FALSE;
}

@ Resources in a Blorb file have unique ID numbers which are positive integers,
but these are not required to start from 1, nor to be contiguous. For Inform,
ID number 1 is reserved for the cover image (whether or not any cover image
is provided: it is legal for there to be figures but no cover, and vice versa).
Other figures, and sound effects, then mix freely as needed from ID number 3
on upwards. We skip 2 so that it can be guaranteed that no sound resource
has ID 1 or 2: this is to help people trying to play sounds in the Z-machine,
where operand 1 or 2 in the |@sound| opcode signifies not a sound resource
number but a long or short beep. If a genuine sound effect had resource ID
1 or 2, therefore, it would be unplayable on the Z-machine.

=
int Projects::get_next_free_blorb_resource_ID(inform_project *project) {
	return project->next_resource_number++;
}

void Projects::set_source_filename(inform_project *project, pathname *P, filename *F) {
	if (P) {
		filename *manifest = Filenames::in_folder(P, I"Contents.txt");
		linked_list *L = NEW_LINKED_LIST(text_stream);
		TextFiles::read(manifest, FALSE,
			NULL, FALSE, Projects::manifest_helper, NULL, (void *) L);
		text_stream *leafname;
		LOOP_OVER_LINKED_LIST(leafname, text_stream, L) {
			build_vertex *S = Graphs::file_vertex(Filenames::in_folder(P, leafname));
			S->annotation = leafname;
			ADD_TO_LINKED_LIST(S, build_vertex, project->source_vertices);
		}
	}
	if ((LinkedLists::len(project->source_vertices) == 0) && (F)) {
		build_vertex *S = Graphs::file_vertex(F);
		S->annotation = I"your source text";
		ADD_TO_LINKED_LIST(S, build_vertex, project->source_vertices);
	}
}

void Projects::manifest_helper(text_stream *text, text_file_position *tfp, void *state) {
	linked_list *L = (linked_list *) state;
	Str::trim_white_space(text);
	wchar_t c = Str::get_first_char(text);
	if ((c == 0) || (c == '#')) return;
	ADD_TO_LINKED_LIST(Str::duplicate(text), text_stream, L);
}

pathname *Projects::path(inform_project *project) {
	if (project == NULL) return NULL;
	return project->as_copy->location_if_path;
}

linked_list *Projects::source(inform_project *project) {
	if (project == NULL) return NULL;
	return project->source_vertices;
}

void Projects::add_kit_dependency(inform_project *project, text_stream *kit_name) {
	RUN_ONLY_BEFORE_PHASE(OPERATIONAL_INBUILD_PHASE)
	if (Projects::uses_kit(project, kit_name)) return;
	linked_list *nest_list = Inbuild::nest_list();
	inform_kit *kit = Kits::load(kit_name, nest_list);
	ADD_TO_LINKED_LIST(kit, inform_kit, project->kits_to_include);
}

int Projects::uses_kit(inform_project *project, text_stream *name) {
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		if (Str::eq(K->as_copy->edition->work->title, name))
			return TRUE;
	return FALSE;
}

void Projects::finalise_kit_dependencies(inform_project *project) {
	RUN_ONLY_IN_PHASE(GOING_OPERATIONAL_INBUILD_PHASE)
	Projects::add_kit_dependency(project, I"BasicInformKit");
	inform_language *L = project->language_of_play;
	if (L) {
		text_stream *kit_name = Languages::kit_name(L);
		Projects::add_kit_dependency(project, kit_name);
	}
	if (project->assumed_to_be_parser_IF)
		Projects::add_kit_dependency(project, I"CommandParserKit");

	int parity = TRUE;
	@<Perform if-this-then-that@>;
	parity = FALSE;
	@<Perform if-this-then-that@>;

	linked_list *sorted = NEW_LINKED_LIST(inform_kit);
	for (int p=0; p<100; p++) {
		inform_kit *K;
		LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
			if (K->priority == p)
				ADD_TO_LINKED_LIST(K, inform_kit, sorted);
	}

	project->kits_to_include = sorted;
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		LOG("Using Inform kit '%S' (priority %d).\n", K->as_copy->edition->work->title, K->priority);
}

@<Perform if-this-then-that@> =
	int changes_made = TRUE;
	while (changes_made) {
		changes_made = FALSE;
		inform_kit *K;
		LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
			if (Kits::perform_ittt(K, project, parity))
				changes_made = TRUE;
	}

@ =
#ifdef CORE_MODULE
void Projects::load_types(inform_project *project) {
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		Kits::load_types(K);
}
#endif

#ifdef CORE_MODULE
void Projects::activate_plugins(inform_project *project) {
	LOG("Activate plugins...\n");
	Plugins::Manage::activate(CORE_PLUGIN_NAME);
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		Kits::activate_plugins(K);
	Plugins::Manage::show(DL, "Included", TRUE);
	Plugins::Manage::show(DL, "Excluded", FALSE);
}
#endif

int Projects::Main_defined(inform_project *project) {
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		if (K->defines_Main)
			return TRUE;
	return FALSE;
}

text_stream *Projects::index_template(inform_project *project) {
	text_stream *I = NULL;
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		if (K->index_template)
			I = K->index_template;
	return I;
}

@ Every source text read into Inform is automatically prefixed by a few words
loading the fundamental "extensions" -- text such as "Include Basic Inform by
Graham Nelson." If Inform were a computer, this would be the BIOS which boots
up its operating system. Each kit can contribute such extensions, so there
may be multiple sentences, which we need to count up.

=
void Projects::early_source_text(OUTPUT_STREAM, inform_project *project) {
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		Kits::early_source_text(OUT, K);
}

int Projects::number_of_early_fed_sentences(inform_project *project) {
	int N = 0;
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include)
		N += Kits::number_of_early_fed_sentences(K);
	return N;
}

#ifdef CODEGEN_MODULE
linked_list *Projects::list_of_inter_libraries(inform_project *project) {
	linked_list *requirements_list = NEW_LINKED_LIST(link_instruction);
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include) {
		link_instruction *link = CodeGen::LinkInstructions::new(
			K->as_copy->location_if_path, K->attachment_point);
		ADD_TO_LINKED_LIST(link, link_instruction, requirements_list);
	}
	return requirements_list;
}
#endif

void Projects::construct_build_target(inform_project *project, target_vm *VM,
	int releasing, int compile_only) {
	pathname *proj = project->as_copy->location_if_path;
	pathname *build_folder = NULL;
	if (proj) build_folder = Pathnames::subfolder(proj, I"Build");

	filename *memory_F = Filenames::in_folder(build_folder, I"memory.interb");
	build_vertex *inter_V = Graphs::file_vertex(memory_F);
	Graphs::need_this_to_build(inter_V, project->as_copy->vertex);
	BuildSteps::attach(inter_V, compile_using_inform7_skill,
		Inbuild::nest_list(), releasing, VM, NULL, project->as_copy);

	filename *inf_F = Filenames::in_folder(build_folder, I"auto.inf");
	build_vertex *inf_V = Graphs::file_vertex(inf_F);
	Graphs::need_this_to_build(inf_V, inter_V);
	BuildSteps::attach(inf_V, code_generate_using_inter_skill,
		Inbuild::nest_list(), releasing, VM, NULL, project->as_copy);

	TEMPORARY_TEXT(story_file_leafname);
	WRITE_TO(story_file_leafname, "output.%S", TargetVMs::get_unblorbed_extension(VM));
	filename *unblorbed_F = Filenames::in_folder(build_folder, story_file_leafname);
	DISCARD_TEXT(story_file_leafname);
	build_vertex *unblorbed_V = Graphs::file_vertex(unblorbed_F);
	Graphs::need_this_to_build(unblorbed_V, inf_V);
	BuildSteps::attach(unblorbed_V, compile_using_inform6_skill,
		Inbuild::nest_list(), releasing, VM, NULL, project->as_copy);

	if (releasing) {
		TEMPORARY_TEXT(story_file_leafname);
		WRITE_TO(story_file_leafname, "output.%S", TargetVMs::get_blorbed_extension(VM));
		filename *blorbed_F = Filenames::in_folder(build_folder, story_file_leafname);
		DISCARD_TEXT(story_file_leafname);
		build_vertex *blorbed_V = Graphs::file_vertex(blorbed_F);
		Graphs::need_this_to_build(unblorbed_V, inf_V);
		BuildSteps::attach(blorbed_V, package_using_inblorb_skill,
			Inbuild::nest_list(), releasing, VM, NULL, project->as_copy);
		project->chosen_build_target = blorbed_V;
	} else project->chosen_build_target = unblorbed_V;
	if (compile_only) {
		project->chosen_build_target = inf_V;
		inf_V->force_this = TRUE;
	}
}

void Projects::construct_graph(inform_project *project) {
	RUN_ONLY_IN_PHASE(GOING_OPERATIONAL_INBUILD_PHASE)
	if (project == NULL) return;
	Projects::finalise_kit_dependencies(project);
	build_vertex *V = project->as_copy->vertex;
	inform_kit *K;
	LOOP_OVER_LINKED_LIST(K, inform_kit, project->kits_to_include) {
		 Graphs::need_this_to_build(V, K->as_copy->vertex);
	}
	build_vertex *S;
	LOOP_OVER_LINKED_LIST(S, build_vertex, project->source_vertices) {
		 Graphs::need_this_to_build(V, S);
	}
	inform_language *L = project->language_of_play;
	if (L) {
		build_vertex *LV = L->as_copy->vertex;
		Graphs::need_this_to_build(V, LV);
	}
	L = project->language_of_syntax;
	if (L) {
		build_vertex *LV = L->as_copy->vertex;
		Graphs::need_this_to_build(V, LV);
	}
	L = project->language_of_index;
	if (L) {
		build_vertex *LV = L->as_copy->vertex;
		Graphs::need_this_to_build(V, LV);
	}
}

@

=
void Projects::read_source_text_for(inform_project *project) {
	TEMPORARY_TEXT(early);
	Projects::early_source_text(early, project);
	if (Str::len(early) > 0) Feeds::feed_stream(early);
	DISCARD_TEXT(early);
	#ifdef CORE_MODULE
	SourceFiles::read_further_mandatory_text();
	#endif
	linked_list *L = Projects::source(project);
	if (L) {
		build_vertex *N;
		LOOP_OVER_LINKED_LIST(N, build_vertex, L) {
			filename *F = N->buildable_if_internal_file;
			N->read_as = SourceText::read_file(project->as_copy, F, N->annotation,
				FALSE, TRUE);
		}
	}
}

int Projects::draws_from_source_file(inform_project *project, source_file *sf) {
	linked_list *L = Projects::source(project);
	if (L) {
		build_vertex *N;
		LOOP_OVER_LINKED_LIST(N, build_vertex, L)
			if (sf == N->read_as)
				return TRUE;
	}
	return FALSE;
}