#version 100

/*
  Shader Modified: Pokefan531
  Color Mangler
  Author: hunterk
  License: Public domain
*/

precision mediump float;
varying vec2 fragTexCoord;
uniform sampler2D texture0;

#define lighten_screen 0.

void main()
{
  vec4 screen = pow(texture2D(texture0, fragTexCoord), vec4(2.2 + (lighten_screen * -1.0))).rgba;
  screen = mix(screen, vec4(0.5), 0.);

  mat4 color = mat4(0.82, 0.125, 0.195, 1., // red channel
                    0.24, 0.665, 0.075, 1., // green channel
                    -0.06, 0.21, 0.73, 1.,  // blue channel
                    0., 0., 0., 1.);        // alpha channel

  mat4 adjust = mat4(1., 0., 0., 1.,
                     0., 1., 0., 1.,
                     0., 0., 1., 1.,
                     0., 0., 0., 1.);

  color *= adjust;
  screen = clamp(screen * 0.94, 0.0, 1.0);
  screen = color * screen;
  gl_FragColor = pow(screen, vec4(1.0 / 2.2));
}
