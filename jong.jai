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

// Timing information and helpers, need to build my intuition for this...
DT_MAX : float : 0.15;
delta: float;
current_dt: float = 0.016667;
last_time:  float64;

LOG_BUFFER_SIZE :: 512;

WINDOW_W :: 640;
WINDOW_H :: 480;

MOVE_SPEED :: 2.0;

key_up, key_down, key_left, key_right : u32;

working_directory_set := false;
base_font: *Simp.Dynamic_Font;

/* Projection, Model, and friends */

ShaderMatrixRef :: struct {
  uni: GLint;
  mat: Matrix4;
}

ViewMats :: struct {
  model: ShaderMatrixRef;
  view: ShaderMatrixRef;
  projection: ShaderMatrixRef;
}

viewMatrices: = ViewMats.{
  .{0, Matrix4_Identity},
  .{0, Matrix4_Identity},
  .{0, Matrix4_Identity},
};

/* Camera variables */

UP :: Vector3.{0, 1.0, 0};

Camera :: struct {
  pos: Vector3;
  target: Vector3;
  direction: Vector3; // Points in reverse?
  right: Vector3;
  up: Vector3;
  // Rotation bits
  looking_at: Vector2;
  rotation: Quaternion;
  pointybits: float;
}

new_camera_pos: Vector3;
camera: Camera;

/* OpenGL variables */
gNullProgramID: GLuint = 99;
glProgram : GLuint;

/* BEGIN SHADER VARIABLES */

mMultiColorLocation: GLint;
gVertexPos2DLocation: GLint;

gVAO: GLuint;
gVBO: GLuint;
gEBO: GLuint;

// Projection matrix
mProjectionMatrix: Matrix4;
mProjectionMatrixLocation: GLint;

// ModelView matrix
mModelViewMatrix: Matrix4;
mModelViewMatrixLocation: GLint;

/* END SHADER VARIABLES */

main :: () {
  // @TODO One day learn more about why we need this, if we do.
  #if OS == .WINDOWS {
    Windows :: #import "Windows";
    Windows.SetProcessDPIAware();
    Windows.timeBeginPeriod(1);
    // This disables prints to console during runtime, fyi.
    // Windows.disable_runtime_console()
  }

  window := create_window(WINDOW_W, WINDOW_H, "My Shenanigans");
  Simp.set_render_target(window);

  print("GL Vendor = %\n", to_string(glGetString(GL_VENDOR)));
  print("GL Version = %\n", to_string(glGetString(GL_VERSION)));

  camera = init_camera();
  new_camera_pos = camera.pos;

  fov := 45.0;
  transform := make_translation_matrix4(camera.pos);

  view_matrix := make_look_at_matrix(
    camera.pos,
    camera.target,
    UP,
    false // x is not forward
  );

  vx, vy, vw, vh := get_dimensions(window, false);
  aspect_ratio := vw / cast (float) vh;

  // Is using a 'minus Z forward matrix' correct here?
  projection_matrix := make_projection_matrix(fov * PI / 180.0, aspect_ratio, 0.1, 100.0);

  // Seems silly to compute this MxN every vertex on the shader, but we can worry about that later.
  viewMatrices.view.mat = view_matrix;
  viewMatrices.projection.mat = projection_matrix;
  // It ... worked ? O.o

  gl_loaded := init_gl();
  if !gl_loaded {
    print("Couldn't initialise shaders and gl program!");
    return;
  }

  // Initiate our font(s)
  init_fonts();

  quit := false;
  move_input : Vector3;

  while !quit {
    move_input = Vector3.{};
    now := seconds_since_init();
    delta : float64 = now - last_time;
    current_dt = cast(float) delta;

    if current_dt > DT_MAX current_dt = DT_MAX;

    last_time = now;

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
    move_input.x = cast (float) is_key_down(xx #char "D") - cast (float) is_key_down(xx #char "A");
    move_input.z = cast (float) is_key_down(xx #char "S") - cast (float) is_key_down(xx #char "W");



    Simp.clear_render_target(.1, .1, .1, 1);
    Simp.update_window(window);

    render_with_gl(delta, move_input);

    Simp.swap_buffers(window);

    if OS != .ANDROID {
      sleep_milliseconds(10);
    }
  };
}

init_camera :: () -> Camera {
  cameraPos := Vector3.{0, 0, 3.0};
  cameraTarget := Vector3.{0, 0, 0};
  cameraDirection := normalize(cameraPos - cameraTarget);
  // The cross product of two vectors is perpendicular to both vectors.
  cameraRight := normalize(cross(UP, cameraDirection));
  cameraUp := cross(cameraRight, cameraDirection);

  return .{
    cameraPos,
    cameraTarget,
    cameraDirection,
    cameraRight,
    cameraUp,
    cameraTarget.xy,
    Quaternion.{},
    0,
  };
}

// Things that we define ourselves but they probably should be
// added to the appropriate modules:
is_key_down :: inline (key : Input.Key_Code) -> bool #must {
	return (Input.input_button_states[cast (s64) key] & .DOWN) != 0;
}

render_with_gl :: (delta_time: float64, move_input: Vector3) {
  // Clear colour buffer
  glClearColor(0.0,0.0,0.0,1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  ROTATION_SMOOTHING := 0.3;
  camera_rot_speed : float = 0.2;
  // rot_quat : Quaternion;
  // set_from_axis_and_angle(*rot_quat, 0, 1, 0, xx (camera_rot_speed * delta_time) * PI / 180.0);
  // Don't start from the identity matrix each time you freaking goober.
  // viewMatrices.model.mat = rotate(translate(viewMatrices.model.mat, move_input), rot_quat);

  mouse_look := xy ( xx Input.mouse_delta_x );
  camera.looking_at = lerp(camera.looking_at, mouse_look, ROTATION_SMOOTHING) * camera_rot_speed;
  camera.pointybits += camera.looking_at.x * PI / 180.0;
  set_from_axis_and_angle(*camera.rotation, 0, -1, 0, camera.pointybits);
  rot_mat := rotation_matrix(Matrix4, camera.rotation);

  // Hrmmmm....
  camera.pos += rotate(unit_vector(move_input), camera.rotation) * (MOVE_SPEED * xx delta_time);

  viewMatrices.model.mat = inverse(make_translation_matrix4(camera.pos) * rot_mat);

  //VBO data, combined cube corners and their respective rgb values.
  // pointData: [24] GLfloat =
    // .[ 0.5,  0.5, 0.0, 0.2, 0.5, 0.0,
    //    0.5, -0.5, 0.0, 0.5, 0.2, 0.0,
    //    -0.5, -0.5, 0.0, 0.0, 0.5, 1.0,
    //    -0.5,  0.5, 0.0, 1.0, 0.0, 0.5
    // ];
  pointData: [3][5] GLfloat =
    .[
      .[-0.5, -0.5, 1.0, 1.0, 0.0],
      .[0.5, -0.5, 0.0, 1.0, 0.0],
      .[0.0, 0.5, 1.0, 0.0, 0.0],
    ];

  indices: [6] GLfloat =
    .[ 0, 1, 3,
       1, 2, 3
     ];

  glGenVertexArrays(1, *gVAO);

  glGenBuffers(1, *gVBO);
  // glGenBuffers(1, *gEBO);

  glBindVertexArray(gVAO);

  // Bind our first VBO to store vertex 2D position data
  glBindBuffer(GL_ARRAY_BUFFER, gVBO);
  // Copy vertex data from the point data array
  glBufferData(GL_ARRAY_BUFFER, 15 * size_of(GLfloat), pointData.data, GL_STATIC_DRAW);

  // Define how we navigate the triangles
  // glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gEBO);
  // glBufferData(GL_ELEMENT_ARRAY_BUFFER, 6 * size_of(GLfloat), indices.data, GL_STATIC_DRAW);

  // Specify that our coordinate data is going to into attribute index 0 and contains three floats.
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * size_of(GLfloat), cast (*void) 0);
  // Enable this attribute index
  glEnableVertexAttribArray(0);

  // Specify that our coordinate data is going to into attribute index 0 and contains two floats.
  glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * size_of(GLfloat), cast (*void) (3 * size_of(GLfloat)));
  // Enable this attribute index
  glEnableVertexAttribArray(1);

  glUniformMatrix4fv(viewMatrices.model.uni, 1, GL_TRUE, *viewMatrices.model.mat._11);
  glUniformMatrix4fv(viewMatrices.view.uni, 1, GL_TRUE, *viewMatrices.view.mat._11);
  glUniformMatrix4fv(viewMatrices.projection.uni, 1, GL_TRUE, *viewMatrices.projection.mat._11);

  glDrawArrays(GL_TRIANGLES, 0, 3);
  // glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, cast (*void) 0);
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
        // Bind quad shader programs.
        glUseProgram(glProgram);
        // Fetch our shader matrix uniforms.
        viewMatrices.model.uni = get_uniform_location(glProgram, "model");
        viewMatrices.view.uni = get_uniform_location(glProgram, "view");
        viewMatrices.projection.uni = get_uniform_location(glProgram, "projection");
      }
    }
  }
  return success;
}


#run {
  set_working_directory(#filepath);
  // main();
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