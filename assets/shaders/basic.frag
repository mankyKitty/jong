#version 330 core

varying vec4 multiColour;
out vec4 FragColour;

void main() {
  FragColour = multiColour;
  // FragColour = vec4( 1.0, 0.0, 1.0, 1.0 );
}