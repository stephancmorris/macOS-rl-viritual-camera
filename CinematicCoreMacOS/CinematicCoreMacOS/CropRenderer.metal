//
//  CropRenderer.metal
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine
//
//  Intentionally empty. CropEngine crops and scales with Core Image (see
//  CropEngine.processCrop); the cropAndScale, cropAndScaleSmooth and
//  cropWithVignette compute kernels that lived here were never dispatched and
//  were removed (CR-046). The file stays because both targets list it in their
//  build membership; git history has the old kernels.
//

#include <metal_stdlib>
