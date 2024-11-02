#import "Basic";
#import "Math";

Input :: #import "Input";
#import "Window_Creation";

#import "System"; // For get_path_of_running_executable. @Cleanup
#import "String"; // for path_strip_filename. @Cleanup

Simp :: #import "Simp";
File :: #import "File";
#import "GL";

#import "shader";

LOG_BUFFER_SIZE :: 512;

WINDOW_W :: 640;
WINDOW_H :: 480;

key_up, key_down, key_left, key_right : u32;

working_directory_set := false;
base_font: *Simp.Dynamic_Font;

gNullProgramID: GLuint = 99;

glProgram : GLuint;

/* BEGIN SHADER VARIABLES */

mMultiColorLocation: GLint;
gVertexPos2DLocation: GLint;

gVAO: GLuint;
gVBO: GLuint;

// Projection matrix
mProjectionMatrix: Matrix4;
mProjectionMatrixLocation: GLint;

// ModelView matrix
mModelViewMatrix: Matrix4;
mModelViewMatrixLocation: GLint;

/* END SHADER VARIABLES */

gRenderQuad :: true;

main :: () {
  // @TODO One day learn more about why we need this, if we do.
  #if OS == .WINDOWS {
    Windows :: #import "Windows";
    Windows.SetProcessDPIAware();
    Windows.timeBeginPeriod(1);
  }

  window := create_window(WINDOW_W, WINDOW_H, "My Shenanigans");
  Simp.set_render_target(window);

  print("GL Vendor = %\n", to_string(glGetString(GL_VENDOR)));
  print("GL Version = %\n", to_string(glGetString(GL_VERSION)));

  gl_loaded := init_gl();
  if !gl_loaded {
    print("Couldn't initialise shaders and gl program!");
    return;
  }

  // Initiate our font(s)
  init_fonts();

  delta_time := 0.01667;
  quit := false;
  while !quit {
    frame_start := current_time_monotonic();

    reset_temporary_storage(); // Reset the local stack
    Input.update_window_events();

    for Input.events_this_frame {
      if it.type == .QUIT then quit = true;
      if it.type == {
        case .KEYBOARD;
          if it.key_code == {
            case .ESCAPE; if it.key_pressed quit = true;
          }
      }
    }

    glViewport(0, 0, xx WINDOW_W, xx WINDOW_H);

    Simp.clear_render_target(.1, .1, .1, 1);
    Simp.update_window(window);

    render_with_gl();

    Simp.swap_buffers(window);

    if OS != .ANDROID {
      sleep_milliseconds(10);
    }
    frame_end := current_time_monotonic();
    delta_time = cast (float) to_float64_seconds(frame_end - frame_start);
  };
}

draw_some_text :: () {
  // Draw some basic text
  // Funky colours !
  time := seconds_since_init();
  theta := cast(float) fmod_cycling(time*3, TAU);
  colour: Vector4;
  colour.x = cos(theta)*.5+.5;
  Clamp(*colour.x, 0, 1);
  colour.y = 1;
  colour.z = cos(theta)*.5+.5;
  Clamp(*colour.z, 0, 1);
  colour.w = 1;

  text := "omg!";
  text_width := Simp.prepare_text(base_font, text);

  text_x := (WINDOW_W - text_width) / 2;
  text_y := WINDOW_H/2 - base_font.character_height/4;

  Simp.draw_prepared_text(base_font, text_x, text_y, colour);
}

get_vert_attrib_location :: (program : GLuint, attrib: *u8) -> GLint {
  out := glGetAttribLocation(program, attrib);
  assert(out != -1, "% is not a valid glsl vertex attribute!", attrib);
  return out;
}

get_uniform_location :: (program: GLuint, uniform: *u8) -> GLint {
  out := glGetUniformLocation(program, uniform);
  assert(out != -1, "% is not a valid glsl program variable!", uniform);
  return out;
}

init_fonts :: () {
  pixel_height := WINDOW_H / 24; // ??
  base_font = Simp.get_font_at_size(sprint("%/%", #filepath, "assets/fonts"), "OpenSans-BoldItalic.ttf", pixel_height);
  assert(base_font != null);
}

init_gl :: () -> bool {
  print_shader_log :: (shader_object: GLuint) {
    log_data: [LOG_BUFFER_SIZE] u8;
    glGetShaderInfoLog(shader_object, log_data.count, null, log_data.data);
    log("%", to_string(log_data.data), flags=.ERROR);
  }
  print_program_log :: (program_object: GLuint) {
    log_data: [LOG_BUFFER_SIZE] u8;
    glGetProgramInfoLog(program_object, log_data.count, null, log_data.data);
    log_error("%", to_string(log_data.data));
  }
  // Success flag
  success := true;
  // Generate program to hold our shaders
  glProgram := glCreateProgram();

  // Create vertex shader
  vertexShader: GLuint = glCreateShader(GL_VERTEX_SHADER);
  defer glDeleteShader(vertexShader);

  vertexShaderSrc, ok := #run File.read_entire_file(sprint("%/%", #filepath, "assets/shaders/basic.vert"));
  if (!ok) {
    print("Failed to load vertex shader!");
    success = false;
  }
  // Set vertex source
  glShaderSource(vertexShader, 1, *vertexShaderSrc.data, null);
  // Compile shader
  glCompileShader(vertexShader);

  // Check the compilation
  vShaderCompiled: GLint;
  glGetShaderiv(vertexShader, GL_COMPILE_STATUS, *vShaderCompiled);
  if ( !vShaderCompiled ) {
    print( "Failed to compile vertex shader, %d\n", vertexShader);
    print_shader_log(vertexShader);
    success = false;
  }
  else {
    // Create the fragment shader
    fragmentShader: GLuint = glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragmentShader);

    // Get shader source
    fragmentShaderSrc, ok := #run File.read_entire_file(sprint("%/%", #filepath, "assets/shaders/basic.frag"));
    if (!ok) {
      print( "Failed to load fragment shader, %d\n", fragmentShader);
      success = false;
    }
    // Attach fragment shader source
    glShaderSource(fragmentShader, 1, *fragmentShaderSrc.data, null);
    // Compile shader
    glCompileShader(fragmentShader);
    fShaderCompiled: GLint;
    glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, *fShaderCompiled);
    if ( !fShaderCompiled ) {
      print("Failed to compile fragment shader: %d\n", fragmentShader);
      print_shader_log(fragmentShader);
      success = false;
    } else {

      // Attach the shaders to the program
      glAttachShader(glProgram, vertexShader);
      glAttachShader(glProgram, fragmentShader);

      // Bind the attributes
      glBindAttribLocation(glProgram, 0, "LVertexPos2D");
      glBindAttribLocation(glProgram, 1, "LMultiColour");

      // Link program
      glLinkProgram(glProgram);

      // Check for errors
      programSuccess: GLint;
      glGetProgramiv(glProgram, GL_LINK_STATUS, *programSuccess);
      if ( !programSuccess ) {
        print("Error linking program: %d\n", glProgram);
        print_program_log(glProgram);
        glDeleteProgram(glProgram);
        success = false;
      } else {

        //VBO data
        pointData: [3][5] GLfloat =
          .[
            .[0.0, 0.5, 1.0, 0.0, 0.0],
            .[0.5, -0.5, 0.0, 1.0, 0.0],
            .[-0.5, -0.5, 1.0, 1.0, 0.0],
          ];

        glGenVertexArrays(1, *gVAO);
        glBindVertexArray(gVAO);

        glGenBuffers(1, *gVBO);

        // Bind our first VBO to store vertex 2D position data
        glBindBuffer( GL_ARRAY_BUFFER, gVBO );
        // Copy vertex data from the point data array
        glBufferData(GL_ARRAY_BUFFER, 15 * size_of(GLfloat), pointData.data, GL_STATIC_DRAW);
        // Specify that our coordinate data is going to into attribute index 0 and contains two floats.
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * size_of(GLfloat), cast (*void) 0);
        // Enable this attribute index
        glEnableVertexAttribArray(0);
        // Specify that our coordinate data is going to into attribute index 0 and contains two floats.
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * size_of(GLfloat), cast (*void) (3 * size_of(GLfloat)));
        // Enable this attribute index
        glEnableVertexAttribArray(1);

        // Bind quad shader programs
        glUseProgram(glProgram);
      }
    }
  }
  return success;
}

render_with_gl :: () {
  // Clear colour buffer
  glClearColor(0.0,0.0,0.0,1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  // // Projection matrix location
  // mProjectionMatrixLocation := get_uniform_location(glProgram, "LProjectionMatrix");
  // // Model View matrix location
  // mModelViewMatrixLocation := get_uniform_location(glProgram, "LModelViewMatrix");

  // mProjectionMatrix = orthographic_projection_matrix(0.0, WINDOW_W, WINDOW_H, 0.0, 1.0, -1.0);
  // glUniformMatrix4fv(mProjectionMatrixLocation, 1, GL_TRUE, *mProjectionMatrix._11);

  // mModelViewMatrix = Matrix4_Identity;
  // glUniformMatrix4fv(mModelViewMatrixLocation, 1, GL_TRUE, *mModelViewMatrix._11);

  // translate(*mModelViewMatrix, .{xx WINDOW_W / 2.0, xx WINDOW_H / 2.0, 0.0});
  // glUniformMatrix4fv(mModelViewMatrixLocation, 1, GL_FALSE, *mModelViewMatrix._11);

  glDrawArrays(GL_TRIANGLES, 0, 3);

  // Disable vertex position
  // glDisableVertexAttribArray(xx gVertexPos2DLocation);
  // glDisableVertexAttribArray(xx mMultiColorLocation);

  glUseProgram(gNullProgramID);
}

#run {
  #if OS == .WINDOWS {
    WR :: #import "Windows_Resources";
    // This disables prints to console during runtime, fyi.
    // WR.disable_runtime_console();
  }
  set_working_directory(#filepath);
  main();
}