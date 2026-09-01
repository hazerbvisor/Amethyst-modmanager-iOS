cmake_minimum_required(VERSION 3.16)
project(AmethystKrypton LANGUAGES C CXX)

if(NOT KRYPTON_SOURCE_DIR)
  message(FATAL_ERROR "KRYPTON_SOURCE_DIR must point to the NG-GL4ES submodule")
endif()
if(NOT EXISTS "${KRYPTON_SOURCE_DIR}/src/gl/gl4es.c")
  message(FATAL_ERROR "Krypton sources are missing. Run: git submodule update --init --recursive")
endif()

set(ENABLE_RTTI ON CACHE BOOL "" FORCE)
set(ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(BUILD_EXTERNAL OFF CACHE BOOL "" FORCE)
set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
set(ENABLE_OPT OFF CACHE BOOL "" FORCE)
set(ENABLE_SPVREMAPPER OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_C_API ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_MSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_STATIC ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SHARED OFF CACHE BOOL "" FORCE)

add_subdirectory("${KRYPTON_SOURCE_DIR}/3rdparty/glslang" glslang EXCLUDE_FROM_ALL)
add_subdirectory("${KRYPTON_SOURCE_DIR}/3rdparty/SPIRV-Cross" spirv-cross EXCLUDE_FROM_ALL)

set(KRYPTON_SOURCES
  src/gl/string_utils.c
  src/gl/cJSON.c
  src/gl/config.c
  src/gl/arbconverter.c
  src/gl/arbgenerator.c
  src/gl/arbhelper.c
  src/gl/arbparser.c
  src/gl/array.c
  src/gl/blend.c
  src/gl/blit.c
  src/gl/buffers.c
  src/gl/build_info.c
  src/gl/debug.c
  src/gl/decompress.c
  src/gl/depth.c
  src/gl/directstate.c
  src/gl/drawing.c
  src/gl/enable.c
  src/gl/envvars.c
  src/gl/eval.c
  src/gl/face.c
  src/gl/fog.c
  src/gl/fpe.c
  src/gl/fpe_cache.c
  src/gl/fpe_shader.c
  src/gl/framebuffers.c
  src/gl/gl_lookup.c
  src/gl/gl4es.c
  src/gl/glstate.c
  src/gl/hint.c
  src/gl/init.c
  src/gl/light.c
  src/gl/line.c
  src/gl/list.c
  src/gl/listdraw.c
  src/gl/listrl.c
  src/gl/loader.c
  src/gl/logs.c
  src/gl/matrix.c
  src/gl/matvec.c
  src/gl/oldprogram.c
  src/gl/pixel.c
  src/gl/planes.c
  src/gl/pointsprite.c
  src/gl/preproc.c
  src/gl/program.c
  src/gl/queries.c
  src/gl/raster.c
  src/gl/render.c
  src/gl/shader.c
  src/gl/shaderconv.c
  src/gl/shader_hacks.c
  src/gl/stack.c
  src/gl/stencil.c
  src/gl/stubs.c
  src/gl/texenv.c
  src/gl/texgen.c
  src/gl/texture.c
  src/gl/texture_compressed.c
  src/gl/texture_params.c
  src/gl/texture_read.c
  src/gl/texture_3d.c
  src/gl/uniform.c
  src/gl/vertexattrib.c
  src/gl/wrap/gl4eswraps.c
  src/gl/wrap/gles.c
  src/gl/wrap/glstub.c
  src/gl/wrap/glesnative.cpp
  src/gl/math/matheval.c
  src/glx/hardext.c
  src/glx/lookup.c
  src/glx/gbm.c
  src/glx/streaming.c
  src/glx/glx.c
  src/gl/vgpu/shaderconv.c
  src/gl/samplers.c
  src/gl/glsl/glsl_for_es.cpp
  src/gl/getter.cpp
)
list(TRANSFORM KRYPTON_SOURCES PREPEND "${KRYPTON_SOURCE_DIR}/")

add_library(krypton SHARED ${KRYPTON_SOURCES})
target_include_directories(krypton PRIVATE "${KRYPTON_SOURCE_DIR}/include")
target_compile_definitions(krypton PRIVATE
  NOX11
  NO_GBM
  DEFAULT_ES=3
)
target_compile_options(krypton PRIVATE
  -O3
  -ffunction-sections
  -fdata-sections
  -fvisibility=hidden
)
target_link_libraries(krypton PRIVATE glslang::glslang spirv-cross-c)

if(APPLE)
  if(NOT KRYPTON_ANGLE_FRAMEWORK_DIR)
    message(FATAL_ERROR "KRYPTON_ANGLE_FRAMEWORK_DIR must contain libEGL and libGLESv2")
  endif()
  target_link_options(krypton PRIVATE
    "-F${KRYPTON_ANGLE_FRAMEWORK_DIR}"
    "-Wl,-dead_strip"
  )
  target_link_libraries(krypton PRIVATE
    "-framework libEGL"
    "-framework libGLESv2"
    "-framework Metal"
    "-framework Foundation"
    "-framework QuartzCore"
  )
endif()

set_target_properties(krypton PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
  CXX_STANDARD 23
  CXX_STANDARD_REQUIRED ON
  OUTPUT_NAME krypton
  INSTALL_NAME_DIR "@rpath"
)
