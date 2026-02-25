//
//  CropRenderer.metal
//  CinematicCoreMacOS
//
//  Created by Stephan Morris on 2/5/2026.
//  Ticket: GFX-01 - Metal Crop Engine
//

#include <metal_stdlib>
using namespace metal;

/// Crop parameters passed from Swift
/// Must match Swift struct layout exactly (32 bytes total)
struct CropParams {
    // Normalized crop rectangle (0-1 coordinates)
    float2 cropOrigin;     // 8 bytes - Bottom-left corner (x, y)
    float2 cropSize;       // 8 bytes - Width and height

    // Output dimensions
    uint2 outputSize;      // 8 bytes

    // Interpolation quality
    float smoothingFactor; // 4 bytes - 0-1, for temporal smoothing
    float _padding;        // 4 bytes - padding for 16-byte alignment
};

/// High-quality bilinear texture sampling
float4 sampleTextureBilinear(
    texture2d<float, access::sample> sourceTexture,
    float2 normalizedCoord
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    return sourceTexture.sample(textureSampler, normalizedCoord);
}

/// Main crop kernel - extracts and scales a region from source texture
kernel void cropAndScale(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant CropParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Early exit for out-of-bounds threads
    if (gid.x >= params.outputSize.x || gid.y >= params.outputSize.y) {
        return;
    }
    
    // Convert output pixel position to normalized coordinates (0-1)
    float2 outputNorm = float2(gid) / float2(params.outputSize);

    // Map to crop region in source texture.
    // cropOrigin is Vision bottom-left origin (Y increases upward).
    // Metal textures use top-left origin (Y increases downward).
    //
    // Output top (outputNorm.y=0) must read the TOP of the Vision crop region.
    // Vision top of crop = cropOrigin.y + cropSize.y
    // Metal Y of that point = 1 - (cropOrigin.y + cropSize.y)
    //
    // Output bottom (outputNorm.y=1) must read the BOTTOM of the Vision crop region.
    // Vision bottom of crop = cropOrigin.y
    // Metal Y of that point = 1 - cropOrigin.y
    //
    // General formula:
    //   sourceNorm.y = (1 - cropOrigin.y - cropSize.y) + outputNorm.y * cropSize.y
    float2 sourceNorm;
    sourceNorm.x = params.cropOrigin.x + outputNorm.x * params.cropSize.x;
    sourceNorm.y = (1.0 - params.cropOrigin.y - params.cropSize.y) + outputNorm.y * params.cropSize.y;
    
    // Sample with bilinear filtering for smooth scaling
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge,
        coord::normalized
    );
    
    float4 color = sourceTexture.sample(textureSampler, sourceNorm);
    
    // Write to output
    outputTexture.write(color, gid);
}

/// Advanced crop kernel with sub-pixel anti-aliasing (for ultra-smooth zooms)
kernel void cropAndScaleSmooth(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant CropParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputSize.x || gid.y >= params.outputSize.y) {
        return;
    }
    
    // Normalized output position
    float2 outputNorm = float2(gid) / float2(params.outputSize);

    // Map to crop region (Vision bottom-left → Metal top-left, corrected Y)
    float2 sourceNorm;
    sourceNorm.x = params.cropOrigin.x + outputNorm.x * params.cropSize.x;
    sourceNorm.y = (1.0 - params.cropOrigin.y - params.cropSize.y) + outputNorm.y * params.cropSize.y;

    // High-quality sampling
    constexpr sampler highQualitySampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge,
        coord::normalized
    );
    
    float4 color = sourceTexture.sample(highQualitySampler, sourceNorm);
    
    outputTexture.write(color, gid);
}

/// Crop with optional vignette effect for cinematic feel (optional enhancement)
kernel void cropWithVignette(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant CropParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputSize.x || gid.y >= params.outputSize.y) {
        return;
    }
    
    float2 outputNorm = float2(gid) / float2(params.outputSize);

    // Map to crop region (Vision bottom-left → Metal top-left, corrected Y)
    float2 sourceNorm;
    sourceNorm.x = params.cropOrigin.x + outputNorm.x * params.cropSize.x;
    sourceNorm.y = (1.0 - params.cropOrigin.y - params.cropSize.y) + outputNorm.y * params.cropSize.y;

    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge,
        coord::normalized
    );

    float4 color = sourceTexture.sample(textureSampler, sourceNorm);

    // Optional: Add subtle vignette for cinematic look
    float2 centerDist = (outputNorm - 0.5) * 2.0; // -1 to 1
    float vignette = 1.0 - (length(centerDist) * 0.3); // Subtle darkening at edges
    vignette = clamp(vignette, 0.0, 1.0);
    
    color.rgb *= vignette;
    
    outputTexture.write(color, gid);
}
