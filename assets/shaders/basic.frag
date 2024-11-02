#version 330 core

in vec3 multiColour;
out vec4 FragColour;

void main() {
  FragColour = vec4(multiColour, 1.0);
  // FragColour = vec4( 1.0, 0.0, 1.0, 1.0 );
}