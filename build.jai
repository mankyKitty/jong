// I don't know how this works yet...
#run build();

build :: () {
  {
    ws := compiler_create_workspace();
    options := get_build_options();
    options.output_executable_name = "jong";
    set_build_options(options, ws);

    add_build_file("jong.jai", ws);
  }
  {
    // No executable for this workspace because this is the build runner.
    set_build_options_dc(.{do_output=false});
  }
}

#import "Basic";
#import "Compiler";