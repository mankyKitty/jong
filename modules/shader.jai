#import "GL";

// In OpenGL land, we write programs in the GLSL language to
// (usually) be executed on the GPU.
// The 'vertex shader' is the first shader to be executed. It
// takes as input the data for a vertex, which we define, and
// it is responsible for transforming that vertex in any way it
// wants (such as applying the model transform, the camera projection).
// The 'fragment shader' is the last shader to be executed. It
// executes per-pixel, and takes as input anything that you want,
// and as output it gives the color of the pixel.
create_shader_program :: (vertex_source : string, fragment_source : string) -> GLuint, bool
{
	check_compile_errors :: (shader : GLuint) -> bool, info_log : string
	{
		success : s32;
		glGetShaderiv (shader, GL_COMPILE_STATUS, *success);
		if !success
		{
			info_len : s32;
			glGetShaderiv (shader, GL_INFO_LOG_LENGTH, *info_len);
			info_data := cast (*u8) alloc (info_len,, temp);
			glGetShaderInfoLog (shader, xx info_len, xx *info_len, info_data);
			result : string;
			result.data = info_data;
			result.count = info_len;

			return false, result;
		}

		return true, "";
	}

	check_link_errors :: (program : GLuint) -> bool, info_log : string
	{
		success : s32;
		glGetProgramiv (program, GL_LINK_STATUS, *success);
		if !success
		{
			info_len : s32;
			glGetProgramiv (program, GL_INFO_LOG_LENGTH, *info_len);
			info_data := cast (*u8) alloc (info_len,, temp);
			glGetProgramInfoLog (program, xx info_len, xx *info_len, info_data);
			result : string;
			result.data = info_data;
			result.count = info_len;

			return false, result;
		}

		return true, "";
	}

	// OpenGL requires us to create at least a vertex shader and a
	// fragment shader, to create a shader program that it can execute.
	vs := glCreateShader (GL_VERTEX_SHADER);
	defer glDeleteShader (vs);

    shaders := *u8.[   SHADER_PREFIX.data ,    vertex_source.data ];
    lengths := s32.[xx SHADER_PREFIX.count, xx vertex_source.count];
	glShaderSource (vs, 2, shaders.data, lengths.data);
	glCompileShader (vs);
	ok, info_log := check_compile_errors (vs);
	if !ok {
		log_error("Could not compile vertex shader %", info_log);
		return 0, false;
	}

	fs := glCreateShader (GL_FRAGMENT_SHADER);
	defer glDeleteShader (fs);
	shaders[1] =    fragment_source.data;
	lengths[1] = xx fragment_source.count;
	glShaderSource (fs, 2, shaders.data, lengths.data);
	glCompileShader (fs);
	ok, info_log = check_compile_errors (fs);
	if !ok {
		log_error ("Could not compile fragment shader: %", info_log);
		return 0, false;
	}

	result := glCreateProgram ();
	glAttachShader (result, vs);
	glAttachShader (result, fs);
	glLinkProgram (result);
	ok, info_log = check_link_errors (result);
	if !ok
	{
		log_error ("Could not link shader program: %", info_log);
		glDeleteProgram (result);
		return 0, false;
	}

	return result, true;
}