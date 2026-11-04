cmake_minimum_required(VERSION 3.16)
project(ChipDeck VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
if(MSVC)
  # Static CRT so chipdeck-cli.exe runs without the VC++ redistributable.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  # Make MSVC report the real C++ standard in __cplusplus (reSIDfp checks it).
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/Zc:__cplusplus>)
endif()

option(CHIPDECK_BUILD_CLI "Build the chipdeck-cli test player" ON)
option(CHIPDECK_BUILD_TESTS "Build tests" ON)

add_subdirectory(third_party)

# ------------------------------------------------------------ chipdeck-core
add_library(chipdeck-core STATIC core/src/chipdeck.cpp)
target_include_directories(chipdeck-core PUBLIC core/include)
target_compile_definitions(chipdeck-core PRIVATE CHIPDECK_VERSION="${PROJECT_VERSION}")
target_link_libraries(chipdeck-core PRIVATE sidplayfp)

# ---------------------------------------------------- chipdeck shared library
# Core + audio output as one DLL/.so for the Flutter app (dart:ffi) and Android.
option(CHIPDECK_BUILD_SHARED "Build the chipdeck shared library" ON)
if(CHIPDECK_BUILD_SHARED)
  set_target_properties(residfp sidplayfp miniaudio PROPERTIES POSITION_INDEPENDENT_CODE ON)
  add_library(chipdeck SHARED core/src/chipdeck.cpp core/src/chipdeck_audio.cpp)
  target_include_directories(chipdeck PUBLIC core/include)
  target_compile_definitions(chipdeck
    PUBLIC CHIPDECK_SHARED
    PRIVATE CHIPDECK_VERSION="${PROJECT_VERSION}")
  set_target_properties(chipdeck PROPERTIES
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
  target_link_libraries(chipdeck PRIVATE sidplayfp miniaudio)
  if(MINGW)
    target_link_options(chipdeck PRIVATE -static -static-libgcc -static-libstdc++)
  endif()
endif()

# -------------------------------------------------------------- chipdeck-cli
if(CHIPDECK_BUILD_CLI)
  add_executable(chipdeck-cli cli/main.cpp)
  target_link_libraries(chipdeck-cli PRIVATE chipdeck-core miniaudio)
endif()

# --------------------------------------------------------------------- tests
if(CHIPDECK_BUILD_TESTS)
  enable_testing()
  add_executable(chipdeck-tests tests/core_test.cpp)
  target_link_libraries(chipdeck-tests PRIVATE chipdeck-core)
  target_compile_definitions(chipdeck-tests PRIVATE
    CHIPDECK_TEST_DATA="${CMAKE_CURRENT_SOURCE_DIR}/tests/data")
  add_test(NAME core COMMAND chipdeck-tests)
endif()
