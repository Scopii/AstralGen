#version 450
layout(location = 0) out vec4 finalColor;

// View:
const vec2 RESOLUTION = vec2(1600.0, 900.0);
const float ASPECT_RATIO = 16.0 / 9.0;
const float FOV_DEGREES = 120.0;  // Field of view in degrees
const float FOCAL_LENGTH = 1.0 / tan(radians(FOV_DEGREES * 0.5)); //FOV degrees to focal length
// Marching:
const int MAX_STEPS = 1024 * 2;
const float MIN_DIST = 0.0001;
const float MAX_DIST = 500.0;
// General:
const float EPSILON = 0.001;
const vec3 CAM = vec3(0.0, 0.0, -5.0);

// SDFs
float sdSphere(vec3 pos, float radius) {
   return length(pos) - radius;
}
// Operations
vec3 opRep(vec3 pos, vec3 spacing) {
   return mod(pos + 0.5 * spacing, spacing) - 0.5 * spacing;
}
// Scene
float map(vec3 pos) {
   vec3 repPos = opRep(pos, vec3(4.0, 4.0, 4.0));
   float sphere = sdSphere(repPos, 0.3);
   //float ground = pos.y + 1.0;
   return sphere;
}
// Functions
vec3 getNormal(vec3 pos) {
   vec3 normal = vec3(
       map(pos + vec3(EPSILON, 0.0, 0.0)) - map(pos - vec3(EPSILON, 0.0, 0.0)),
       map(pos + vec3(0.0, EPSILON, 0.0)) - map(pos - vec3(0.0, EPSILON, 0.0)),
       map(pos + vec3(0.0, 0.0, EPSILON)) - map(pos - vec3(0.0, 0.0, EPSILON))
   );
   return normalize(normal);
}

// MAIN PROGRAM
void main() {
   vec2 uv = (gl_FragCoord.xy / RESOLUTION) * 2.0 - 1.0;
   vec3 rayDir = normalize(vec3(uv.x * ASPECT_RATIO, -uv.y, FOCAL_LENGTH));  // + ASPECT_RATIO calc
   
   float march = 0.0;
   bool hit = false;
   vec3 pos;
   
   // Ray Marching
   for(int step = 0; step < MAX_STEPS; step++) {
       pos = CAM + rayDir * march;
       float closest = map(pos);
       
       if(closest < MIN_DIST) {
           hit = true;
           break;
       }
       
       march += closest;
       if(march > MAX_DIST) break;
   }
   
   if(hit) {
       vec3 normal = getNormal(pos);
       vec3 lightDir = normalize(vec3(1.0, 1.0, -1.0));
       float lighting = max(dot(normal, lightDir), 0.1);
       vec3 surfaceColor = vec3(1.0, 0.0, 0.0);
       finalColor = mix(vec4(surfaceColor * lighting, 1.0), vec4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);

   } else finalColor = vec4(0.0, 0.0, 0.0, 1.0);
}