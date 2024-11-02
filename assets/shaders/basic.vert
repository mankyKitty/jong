#version 330 core

// uniform mat4 LProjectionMatrix;
// uniform mat4 LModelViewMatrix;

layout (location = 0) in vec2 LVertexPos2D;
layout (location = 1) in vec3 LMultiColour;

out vec3 multiColour;

void main() {
  multiColour = LMultiColour;
  // gl_Position = LProjectionMatrix * LModelViewMatrix * vec4(LVertexPos2D, 0, 1 );
  gl_Position = vec4(LVertexPos2D, 0, 1 );
}