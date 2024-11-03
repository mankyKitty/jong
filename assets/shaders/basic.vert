#version 330 core

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

layout (location = 0) in vec2 LVertexPos2D;
layout (location = 1) in vec3 LMultiColour;

out vec3 multiColour;

void main() {
  multiColour = LMultiColour;
  gl_Position = projection * view * model * vec4(LVertexPos2D, 0, 1 );
}