#version 100       
precision mediump float;// Precision required for OpenGL ES2 (WebGL)
varying vec2 fragTexCoord;         
varying vec4 fragColor;            
uniform sampler2D texture0;
uniform vec4 colDiffuse;
void main()
{          
    vec4 texelColor = texture2D(texture0, vec2(fragTexCoord.x, 1.0-fragTexCoord.y));
    gl_FragColor = texelColor*colDiffuse*fragColor;      
}