#version 330

in vec4 fragColor;
in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

void main() {
    vec4 color = texture(texture0, vec2(fragTexCoord.x, 1.0 - fragTexCoord.y));
    float alpha = 1.0;
    //finalColor = colDiffuse
    finalColor = vec4(color.xyz, alpha);
}