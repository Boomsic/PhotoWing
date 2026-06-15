#include <metal_stdlib>
using namespace metal;

/// 电影调色着色器
/// 输入：相机帧纹理
/// 输出：经过色彩矩阵 + 对比度 + 饱和度调整的画面

struct ColorGradeUniforms {
    float3x3 colorMatrix;      // 3x3 RGB 变换矩阵
    float    brightnessOffset; // 亮度偏移
    float    saturationScale;  // 饱和度缩放
    float    contrastGamma;    // 对比度 gamma
    float    filmGrain;        // 胶片颗粒强度 0-0.1
    float    time;             // 时间（用于颗粒随机种子）
};

// MARK: - 主着色器

kernel void cinematicGrade(texture2d<float, access::read>  inTexture  [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            constant ColorGradeUniforms& uniforms    [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]])
{
    // 边界检查
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 inColor = inTexture.read(gid);

    // 1. 色彩矩阵变换
    float3 rgb = float3(inColor.r, inColor.g, inColor.b);
    float3 graded = uniforms.colorMatrix * rgb;

    // 2. 亮度偏移
    graded += uniforms.brightnessOffset;
    graded = clamp(graded, 0.0, 1.0);

    // 3. 饱和度调整
    float luminance = dot(graded, float3(0.299, 0.587, 0.114));
    graded = mix(float3(luminance), graded, uniforms.saturationScale);

    // 4. 对比度（gamma 曲线）
    graded = pow(max(graded, 0.0), float3(uniforms.contrastGamma));

    // 5. 胶片颗粒（可选的噪点叠加，给电影感）
    if (uniforms.filmGrain > 0.001) {
        // 简单哈希生成伪随机噪点
        float noise = fract(sin(dot(float2(gid) * 0.001, float2(12.9898, 78.233)) + uniforms.time) * 43758.5453);
        float grain = (noise - 0.5) * uniforms.filmGrain;
        graded += grain;
        graded = clamp(graded, 0.0, 1.0);
    }

    outTexture.write(float4(graded, inColor.a), gid);
}

// MARK: - 遮幅着色器（效率高，直接覆盖黑色）

kernel void letterboxOverlay(texture2d<float, access::read_write> inOutTexture [[texture(0)]],
                              constant float& topBarHeight    [[buffer(0)]],
                              constant float& bottomBarHeight [[buffer(1)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= inOutTexture.get_width() || gid.y >= inOutTexture.get_height()) {
        return;
    }

    // y 坐标在遮幅区域内 → 涂黑
    if (gid.y < uint(topBarHeight) || gid.y >= inOutTexture.get_height() - uint(bottomBarHeight)) {
        inOutTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
    }
}
