#version 450
layout(location = 0) in vec3 fragColor;
layout(location = 0) out vec4 finalColor;

// Constants
const vec2 RESOLUTION = vec2(1600.0, 900.0);
const float ASPECT = 16.0 / 9.0;
const float FOV_DEGREES = 120.0;  // Field of view in degrees
const int MAX_STEPS = 1024 * 2 * 2 * 2;
const float HIT_DIST = 0.0001;
const float MAX_DIST = 1000.0;
const float EPSILON = 0.001;

// Convert FOV degrees to focal length for ray direction
const float FOCAL_LENGTH = 1.0 / tan(radians(FOV_DEGREES * 0.5));

// Repeat space infinitely
vec3 opRep(vec3 pos, vec3 spacing) {
   return mod(pos + 0.5 * spacing, spacing) - 0.5 * spacing;
}

float sdSphere(vec3 pos, float radius) {
   return length(pos) - radius;
}

float sdBox(vec3 pos, vec3 size) {
   vec3 dist = abs(pos) - size;
   return length(max(dist, 0.0)) + min(max(dist.x, max(dist.y, dist.z)), 0.0);
}

float map(vec3 pos) {
   // Repeat objects every 4 units in X and Z
   vec3 repPos = opRep(pos, vec3(4.0, 4.0, 4.0));
   
   float sphere = sdSphere(repPos, 0.3);
   float box = sdBox(pos - vec3(1.5, 0.0, 0.0), vec3(0.5));
   float ground = pos.y + 1.5;
   
   return min(sphere, box);
}

vec3 getNormal(vec3 pos) {
   vec3 normal = vec3(
       map(pos + vec3(EPSILON, 0.0, 0.0)) - map(pos - vec3(EPSILON, 0.0, 0.0)),
       map(pos + vec3(0.0, EPSILON, 0.0)) - map(pos - vec3(0.0, EPSILON, 0.0)),
       map(pos + vec3(0.0, 0.0, EPSILON)) - map(pos - vec3(0.0, 0.0, EPSILON))
   );
   return normalize(normal);
}

void main() {
   vec2 uv = (gl_FragCoord.xy / RESOLUTION) * 2.0 - 1.0;
   uv.x *= ASPECT;
   
   vec3 camPos = vec3(0.0, 0.0, -5.0);
   vec3 rayDir = normalize(vec3(uv.x, -uv.y, FOCAL_LENGTH));  // Uses focal length for proper FOV
   
   float dist = 0.0;
   vec3 pos;
   bool hit = false;
   
   for(int i = 0; i < MAX_STEPS; i++) {
       pos = camPos + rayDir * dist;
       float d = map(pos);
       
       if(d < HIT_DIST) {
           hit = true;
           break;
       }
       
       dist += d;
       if(dist > MAX_DIST) break;
   }
   
   if(hit) {
       vec3 normal = getNormal(pos);
       vec3 lightDir = normalize(vec3(1.0, 1.0, -1.0));
       
       float lighting = max(dot(normal, lightDir), 0.1);
       vec3 surfaceColor = vec3(0.8, 0.4, 0.2);
       
       finalColor = vec4(surfaceColor * lighting, 1.0);
   } else {
       finalColor = vec4(0.0, 0.0, 0.0, 1.0);
   }
}