#import "Basic";
#import "Math";

#import "Input";
#import "Window_Creation";

#import "System"; // For get_path_of_running_executable. @Cleanup
#import "String"; // for path_strip_filename. @Cleanup

Simp :: #import "Simp";
File :: #import "File";
#import "GL";
#import "SDL";

#import "shader";

LOG_BUFFER_SIZE :: 512;

WINDOW_W :: 640;
WINDOW_H :: 480;

PLAYER_FLOOR :: 20;
PLAYER_CEILING :: WINDOW_H / 2;

LEFT_WALL :: 120;
RIGHT_WALL :: WINDOW_W - LEFT_WALL;

GameState :: struct {
}

Player :: struct {
  position: Vector2;
  colour: Vector4;
  size: float;
  speed: float;
}

key_up, key_down, key_left, key_right : u32;

working_directory_set := false;
base_font: *Simp.Dynamic_Font;

gNullProgramID: GLuint = 99;

gProgramID: GLuint = 0;

/* BEGIN SHADER VARIABLES */

mMultiColorLocation: GLint;
gVertexPos2DLocation: GLint;

gVBO: GLuint  = 0;
gIBO: GLuint  = 0;

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

  SDL_Init(SDL_INIT_VIDEO);

  window := SDL_CreateWindow("An SDL2 window", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, WINDOW_W, WINDOW_H, SDL_WINDOW_OPENGL|SDL_WINDOW_RESIZABLE);

  // Check that the window was successfully created
  if window == null {
      // In the case that the window could not be made...
      print("Could not create window: %\n", to_string(SDL_GetError()));
      return;
  }

  // SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  // SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);

  gl_context := SDL_GL_CreateContext(window);
  if !gl_context {
      print( "Could not create OpenGL context: %\n", to_string(SDL_GetError()));
      return;
  }

  gl_load(*gl, SDL_GL_GetProcAddress);

  print("GL Vendor = %\n", to_string(glGetString(GL_VENDOR)));
  print("GL Version = %\n", to_string(glGetString(GL_VERSION)));

  gl_loaded := init_gl();
  if !gl_loaded {
    print("Couldn't initialise shaders and gl program!");
    return;
  }

  // Initiate our font(s)
  init_fonts();

  // Initiate our player wiggle
  player: Player;
  player.position = Vector2.{WINDOW_W / 2, 20};
  player.size = 15.0;
  player.colour = Vector4.{.9,.3,.0,.1};
  player.speed = 250.0;

  // Initial quit status
  quitting := false;

  // Frame timing
  lastFrame := seconds_since_init();
  deltaTime : float;

  exit := false;
  while !exit {
      event : SDL_Event;
      while SDL_PollEvent(*event) {
          if event.type == {
              case SDL_QUIT;
                  exit = true;
              case SDL_KEYUP;
                  if event.key.keysym.sym == SDLK_ESCAPE exit = true;
              // case SDL_WINDOWEVENT;
              //     if event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED {
              //         w = event.window.data1;
              //         h = event.window.data2;
              //     }
          }
      }

  // while !quitting {
  //   frameStart := seconds_since_init();
  //   dt : float64 = frameStart - lastFrame;
  //   deltaTime = cast(float) dt;
  //   lastFrame = frameStart;

  //   update_window_events();

  //   for event : events_this_frame {
  //     quitting = (event.key_code == .ESCAPE && event.key_pressed) || event.type == .QUIT;

  //     if event.type == {
  //       case .KEYBOARD;
  //       kc := event.key_code;
  //       if kc == .ARROW_UP    key_up = event.key_pressed;
  //       if kc == .ARROW_LEFT  key_left = event.key_pressed;
  //       if kc == .ARROW_RIGHT key_right = event.key_pressed;
  //     }
  //   }

    dx : Vector2;
    if key_up    dx.y += player.speed;
    if key_left  dx.x -= player.speed;
    if key_right dx.x += player.speed;

    // Move the player back to the floor if they stop advancing.
    if !key_up && player.position.y > PLAYER_FLOOR {
      dx.y -= player.speed / 2;
    }

    player.position += dx * deltaTime;
    // Clamp player vertical movement
    Clamp(*player.position.y, PLAYER_FLOOR, PLAYER_CEILING);
    // Clamp player horizontal movement
    Clamp(*player.position.x, LEFT_WALL, RIGHT_WALL);

    glViewport(0, 0, xx WINDOW_W, xx WINDOW_H);

    render_with_gl();

    SDL_GL_SwapWindow(window);

    sleep_milliseconds(10);
    reset_temporary_storage(); // Reset the local stack
  };

  SDL_DestroyWindow(window);
  SDL_Quit();
}

draw_one_frame :: (player: Player) {
  // immediate_quad :: (x0: float, y0: float, x1: float, y1: float, color: Vector4)
  Simp.immediate_quad(
    player.position.x - player.size,
    player.position.y - player.size,
    player.position.x + player.size,
    player.position.y + player.size,
    player.colour
  );
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

PointColour :: struct {
  pos: Vector2;
  rgba: Vector4;
}

init_fonts :: () {
  if !working_directory_set {
    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);
    working_directory_set = true;
  }
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
    // Attach the shader to the program
    glAttachShader(glProgram, vertexShader);

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
      // Attach fragment shader to program
      glAttachShader(glProgram, fragmentShader);

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
        // Get vertex attribute location
        // gVertexPos2DLocation = glGetAttribLocation(glProgram, "LVertexPos2D");
        // assert(gVertexPos2DLocation != -1, "LVertexPos2D is not a valid glsl program variable!!");
        gVertexPos2DLocation = get_vert_attrib_location(glProgram, "LVertexPos2D");
        mMultiColorLocation = get_vert_attrib_location(glProgram, "LMultiColour");

        // Projection matrix location
        mProjectionMatrixLocation := get_uniform_location(glProgram, "LProjectionMatrix");
        // Model View matrix location
        mModelViewMatrixLocation := get_uniform_location(glProgram, "LModelViewMatrix");

        // orthographic_projection_matrix :: (
        //   left: float,
        //   right: float,
        //   bottom: float,
        //   top: float,
        //   near: float,
        //   far: float,
        //   depth_range_01:=false) -> Matrix4

        mProjectionMatrix = orthographic_projection_matrix(0.0, WINDOW_W, WINDOW_H, 0.0, 1.0, -1.0);
        glUniformMatrix4fv(mProjectionMatrixLocation, 1, GL_FALSE, *mProjectionMatrix._11);

        mModelViewMatrix = Matrix4_Identity;
        glUniformMatrix4fv(mModelViewMatrixLocation, 1, GL_FALSE, *mModelViewMatrix._11);

        // Everything is loaded and compiled and we can start send vertex data.
        glClearColor(0.0, 0.0, 0.0, 1.0);

        //VBO data
        // Struggling to get this to actually render a colour ..
        renderdata: [4] PointColour =
          .[
            .{.{-0.5, -0.5}, .{1.0, 0.0, 0.0, 1.0} },
            .{.{0.5, -0.5}, .{1.0, 1.0, 0.0, 1.0} },
            .{.{0.5, 0.5}, .{0.0, 1.0, 0.0, 1.0} },
            .{.{-0.5, 0.5}, .{0.0, 0.0, 1.0, 1.0} }
          ];

        vertexData: [8] GLfloat =
          .[
            -0.5, -0.5,
            0.5, -0.5,
            0.5, 0.5,
            -0.5, 0.5
          ];
        indexData: [4] GLuint = .[0, 1, 2, 3];

        glGenBuffers(1, *gVBO);
        glBindBuffer( GL_ARRAY_BUFFER, gVBO );
        // glBufferData( GL_ARRAY_BUFFER, 2 * 4 * size_of(GLfloat), *vertexData, GL_STATIC_DRAW );
        glBufferData( GL_ARRAY_BUFFER, 4 * size_of(PointColour), *renderdata, GL_STATIC_DRAW );

        //Create IBO
        glGenBuffers( 1, *gIBO );
        glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, gIBO );
        glBufferData( GL_ELEMENT_ARRAY_BUFFER, 4 * size_of(GLuint), *indexData, GL_STATIC_DRAW );


      }
    }
  }
  return success;
}

render_with_gl :: () {
  // Clear colour buffer
  glClear(GL_COLOR_BUFFER_BIT);

  // glEnable (GL_BLEND);
  // glBlendFunc (GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR);

  translate(*mModelViewMatrix, .{xx WINDOW_W / 2.0, xx WINDOW_H / 2.0, 0.0});
  glUniformMatrix4fv(mModelViewMatrixLocation, 1, GL_FALSE, *mModelViewMatrix._11);

  // Bind quad shader programs
  glUseProgram(gProgramID);

  // Enable vertex position
  glEnableVertexAttribArray(xx gVertexPos2DLocation);
  glEnableVertexAttribArray(xx mMultiColorLocation);

  // Set vertex data
  glBindBuffer(GL_ARRAY_BUFFER, gVBO);
  // glVertexAttribPointer( xx gVertexPos2DLocation, 2, GL_FLOAT, GL_FALSE, 2 * size_of(GLfloat), null);

  glVertexAttribPointer( xx gVertexPos2DLocation, 2, GL_FLOAT, GL_FALSE, size_of(PointColour), cast (*void) 0);
  glVertexAttribPointer( xx mMultiColorLocation, 4, GL_FLOAT, GL_FALSE, size_of(PointColour), cast (*void) (size_of(Vector2)));

  // Set index data and render
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gIBO);
  glDrawElements(GL_TRIANGLE_FAN, 4, GL_UNSIGNED_INT, null);

  // Disable vertex position
  glDisableVertexAttribArray(xx gVertexPos2DLocation);
  glDisableVertexAttribArray(xx mMultiColorLocation);

  // Unbind program
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