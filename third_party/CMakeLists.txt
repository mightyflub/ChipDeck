# CMake build for vendored third-party libraries.
# Upstream libsidplayfp/libresidfp use autotools; this file replaces that so the
# same sources build with MSVC, MinGW, GCC/Clang and the Android NDK.
# Sources are unmodified copies of the upstream release tarballs (see README.md).

# ---------------------------------------------------------------- libresidfp
set(RESIDFP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libresidfp)
set(RESIDFP_GEN ${CMAKE_CURRENT_BINARY_DIR}/residfp-gen)

if(MSVC)
  set(HAVE_BUILTIN_EXPECT 0)
else()
  set(HAVE_BUILTIN_EXPECT 1)
endif()
set(RESIDFP_BRANCH_HINTS 1)
set(RESIDFP_INLINING 1)
set(RESIDFP_INLINE inline)
set(PACKAGE_VERSION 1.2.3)
set(LIB_MAJOR 1)
set(LIB_MINOR 2)
set(LIB_LEVEL 3)
configure_file(${RESIDFP_DIR}/src/siddefs-fp.h.in ${RESIDFP_GEN}/siddefs-fp.h @ONLY)
configure_file(${RESIDFP_DIR}/src/residfp/sidversion.h.in ${RESIDFP_GEN}/residfp/sidversion.h @ONLY)

add_library(residfp STATIC
  ${RESIDFP_DIR}/src/Dac.cpp
  ${RESIDFP_DIR}/src/EnvelopeGenerator.cpp
  ${RESIDFP_DIR}/src/ExternalFilter.cpp
  ${RESIDFP_DIR}/src/Filter.cpp
  ${RESIDFP_DIR}/src/Filter6581.cpp
  ${RESIDFP_DIR}/src/Filter8580.cpp
  ${RESIDFP_DIR}/src/FilterModelConfig.cpp
  ${RESIDFP_DIR}/src/FilterModelConfig6581.cpp
  ${RESIDFP_DIR}/src/FilterModelConfig8580.cpp
  ${RESIDFP_DIR}/src/Integrator6581.cpp
  ${RESIDFP_DIR}/src/Integrator8580.cpp
  ${RESIDFP_DIR}/src/OpAmp.cpp
  ${RESIDFP_DIR}/src/SID.cpp
  ${RESIDFP_DIR}/src/Spline.cpp
  ${RESIDFP_DIR}/src/State.cpp
  ${RESIDFP_DIR}/src/WaveformCalculator.cpp
  ${RESIDFP_DIR}/src/WaveformGenerator.cpp
  ${RESIDFP_DIR}/src/resample/SincResampler.cpp
  ${RESIDFP_DIR}/src/version.cc
  ${RESIDFP_DIR}/src/residfp/residfp.cpp
)
target_include_directories(residfp
  PUBLIC  ${RESIDFP_DIR}/src ${RESIDFP_GEN})
target_compile_definitions(residfp PRIVATE $<$<NOT:$<CONFIG:Debug>>:NDEBUG>)
if(WIN32)
  target_compile_definitions(residfp PRIVATE WIN32_LEAN_AND_MEAN)
endif()
find_package(Threads REQUIRED)
target_link_libraries(residfp PUBLIC Threads::Threads)

# -------------------------------------------------------------- libsidplayfp
set(SIDPLAYFP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libsidplayfp)
set(SIDPLAYFP_GEN ${CMAKE_CURRENT_BINARY_DIR}/sidplayfp-gen)
set(LIB_MAJOR 3)
set(LIB_MINOR 1)
set(LIB_LEVEL 2)
configure_file(${SIDPLAYFP_DIR}/src/sidplayfp/sidversion.h.in ${SIDPLAYFP_GEN}/sidplayfp/sidversion.h @ONLY)
configure_file(${SIDPLAYFP_DIR}/src/builders/sidlite-builder/sidlite/sl_defs.h.in
               ${SIDPLAYFP_GEN}/sl_defs.h @ONLY)

set(S ${SIDPLAYFP_DIR}/src)
add_library(sidplayfp STATIC
  ${S}/EventScheduler.cpp
  ${S}/player.cpp
  ${S}/psiddrv.cpp
  ${S}/reloc65.cpp
  ${S}/simpleMixer.cpp
  ${S}/sidemu.cpp
  ${S}/c64/c64.cpp
  ${S}/c64/mmu.cpp
  ${S}/c64/VIC_II/mos656x.cpp
  ${S}/c64/CPU/mos6510.cpp
  ${S}/c64/CPU/mos6510debug.cpp
  ${S}/c64/CIA/interrupt.cpp
  ${S}/c64/CIA/mos652x.cpp
  ${S}/c64/CIA/SerialPort.cpp
  ${S}/c64/CIA/timer.cpp
  ${S}/c64/CIA/tod.cpp
  ${S}/sidplayfp/sidplayfp.cpp
  ${S}/sidplayfp/sidbuilder.cpp
  ${S}/sidplayfp/SidConfig.cpp
  ${S}/sidplayfp/SidInfo.cpp
  ${S}/sidplayfp/SidTune.cpp
  ${S}/sidplayfp/SidTuneInfo.cpp
  ${S}/sidtune/MUS.cpp
  ${S}/sidtune/p00.cpp
  ${S}/sidtune/prg.cpp
  ${S}/sidtune/PSID.cpp
  ${S}/sidtune/SidTuneBase.cpp
  ${S}/sidtune/SidTuneTools.cpp
  ${S}/utils/iniParser.cpp
  ${S}/utils/SidDatabase.cpp
  ${S}/utils/STILview/stil.cpp
  # builders
  ${S}/builders/residfp-builder/residfp-builder.cpp
  ${S}/builders/residfp-builder/residfp-emu.cpp
  ${S}/builders/sidlite-builder/sidlite-builder.cpp
  ${S}/builders/sidlite-builder/sidlite-emu.cpp
  ${S}/builders/sidlite-builder/sidlite/ADSR.cpp
  ${S}/builders/sidlite-builder/sidlite/Filter.cpp
  ${S}/builders/sidlite-builder/sidlite/SID.cpp
  ${S}/builders/sidlite-builder/sidlite/WavGen.cpp
)
target_include_directories(sidplayfp
  PUBLIC  ${S} ${S}/utils ${SIDPLAYFP_GEN}
  PRIVATE ${S}/builders/sidlite-builder/sidlite ${S}/sidtune ${S}/libs/hashlib)
# config.h normally tells libsidplayfp which C++ standard it has; we build as C++17.
target_compile_definitions(sidplayfp PUBLIC HAVE_CXX17)
target_compile_definitions(sidplayfp PRIVATE
  PACKAGE_NAME="libsidplayfp" PACKAGE_VERSION="3.1.2" VERSION="3.1.2"
  PACKAGE_URL="https://github.com/libsidplayfp/libsidplayfp"
  HAVE_RESIDFP=1
  $<$<NOT:$<CONFIG:Debug>>:NDEBUG>)
if(WIN32)
  target_compile_definitions(sidplayfp PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
else()
  target_compile_definitions(sidplayfp PRIVATE HAVE_STRCASECMP=1 HAVE_STRNCASECMP=1)
endif()
target_link_libraries(sidplayfp PUBLIC residfp)

# ----------------------------------------------------------------- miniaudio
add_library(miniaudio STATIC ${CMAKE_CURRENT_SOURCE_DIR}/miniaudio/miniaudio.c)
target_include_directories(miniaudio PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/miniaudio)
target_compile_definitions(miniaudio PUBLIC MA_NO_ENCODING MA_NO_DECODING MA_NO_GENERATION)
if(UNIX AND NOT APPLE AND NOT ANDROID)
  target_link_libraries(miniaudio PUBLIC ${CMAKE_DL_LIBS} m)
endif()
if(ANDROID)
  target_link_libraries(miniaudio PUBLIC OpenSLES log)
endif()

# --------------------------------------------------------------- AtariAudio
# Atari ST .sndh and .ym playback (68000 + YM2149 + MFP + STE DAC emulation).
# Plain C++ with no dependencies; same source list as upstream's
# example/AtariAudio2Wav/CMakeLists.txt.
set(AA ${CMAKE_CURRENT_SOURCE_DIR}/atariaudio/src)
add_library(atariaudio STATIC
  ${AA}/AtariAudioRenderer.cpp
  ${AA}/AtariMachine.cpp
  ${AA}/Blitter.cpp
  ${AA}/Mk68901.cpp
  ${AA}/SndhRenderer.cpp
  ${AA}/SteDac.cpp
  ${AA}/timedb.cpp
  ${AA}/ym2149c.cpp
  ${AA}/YmRenderer.cpp
  ${AA}/external/ice_24.cpp
  ${AA}/external/lzh.cpp
  ${AA}/external/Musashi/m68k.cpp
  ${AA}/external/Musashi/m68kcpu.cpp
  ${AA}/external/Musashi/m68kops.cpp
)
target_include_directories(atariaudio PUBLIC ${AA})
target_compile_definitions(atariaudio PRIVATE $<$<NOT:$<CONFIG:Debug>>:NDEBUG>)
if(MSVC)
  target_compile_definitions(atariaudio PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

# ------------------------------------------------------------------ libxmp
# Amiga .mod and other tracker modules. Plain C; source lists from upstream
# cmake/libxmp-sources.cmake (paths relative to the libxmp folder).
set(XMP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libxmp)
include(${XMP_DIR}/cmake/libxmp-sources.cmake)
set(XMP_SRC ${LIBXMP_SRC_LIST} ${LIBXMP_SRC_LIST_PROWIZARD} ${LIBXMP_SRC_LIST_DEPACKERS})
list(TRANSFORM XMP_SRC PREPEND ${XMP_DIR}/)
add_library(xmp STATIC ${XMP_SRC})
target_include_directories(xmp PUBLIC ${XMP_DIR}/include)
target_compile_definitions(xmp PUBLIC LIBXMP_STATIC)
if(MSVC)
  target_compile_definitions(xmp PRIVATE _USE_MATH_DEFINES _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_definitions(xmp PRIVATE _REENTRANT HAVE_POWF=1)
  if(NOT WIN32)
    target_compile_definitions(xmp PRIVATE HAVE_UNISTD_H=1 HAVE_MKSTEMP=1 HAVE_UMASK=1)
  endif()
endif()
if(UNIX)
  target_link_libraries(xmp PUBLIC m)
endif()

# ------------------------------------------------------- libtfmxaudiodecoder
# Amiga TFMX (Chris Huelsbeck) and Jochen Hippel TFMX / Future Composer.
# C++; upstream builds with autotools, this replaces it (Config.h is ours).
set(TFMX_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libtfmxaudiodecoder/src)
add_library(tfmxdec STATIC
  ${TFMX_DIR}/tfmxaudiodecoder.cpp
  ${TFMX_DIR}/Decoder.cpp
  ${TFMX_DIR}/DecoderProxy.cpp
  ${TFMX_DIR}/CRCLight.cpp
  ${TFMX_DIR}/Dump.cpp
  ${TFMX_DIR}/Filter.cpp
  ${TFMX_DIR}/PaulaVoice.cpp
  ${TFMX_DIR}/LamePaulaVoice.cpp
  ${TFMX_DIR}/LamePaulaMixer.cpp
  ${TFMX_DIR}/Chris/TFMXDecoder.cpp
  ${TFMX_DIR}/Chris/Macro.cpp
  ${TFMX_DIR}/Chris/Modulation.cpp
  ${TFMX_DIR}/Chris/Pattern.cpp
  ${TFMX_DIR}/Chris/Sequencer.cpp
  ${TFMX_DIR}/Chris/Songs.cpp
  ${TFMX_DIR}/Chris/ByChecksum.cpp
  ${TFMX_DIR}/Chris/SamplesFile.cpp
  ${TFMX_DIR}/Chris/MergedFiles.cpp
  ${TFMX_DIR}/Chris/DNS/DNSDecoder.cpp
  ${TFMX_DIR}/Jochen/HippelDecoder.cpp
  ${TFMX_DIR}/Jochen/Analyze.cpp
  ${TFMX_DIR}/Jochen/COSO.cpp
  ${TFMX_DIR}/Jochen/Envelope.cpp
  ${TFMX_DIR}/Jochen/FC.cpp
  ${TFMX_DIR}/Jochen/Instrument.cpp
  ${TFMX_DIR}/Jochen/MCMD.cpp
  ${TFMX_DIR}/Jochen/ModPack.cpp
  ${TFMX_DIR}/Jochen/Portamento.cpp
  ${TFMX_DIR}/Jochen/Probe.cpp
  ${TFMX_DIR}/Jochen/SMOD.cpp
  ${TFMX_DIR}/Jochen/TFMX7V.cpp
  ${TFMX_DIR}/Jochen/TFMX.cpp
  ${TFMX_DIR}/Jochen/TraitsByChecksum.cpp
  ${TFMX_DIR}/Jochen/Vibrato.cpp)
target_include_directories(tfmxdec PUBLIC ${TFMX_DIR})
target_compile_features(tfmxdec PRIVATE cxx_std_17)
if(MSVC)
  # Upstream uses the alternative token "and"; MSVC needs <iso646.h> for it.
  target_compile_options(tfmxdec PRIVATE /FIiso646.h)
endif()

if(MSVC)
  foreach(t residfp sidplayfp miniaudio atariaudio xmp tfmxdec)
    target_compile_options(${t} PRIVATE /W0 /utf-8)
  endforeach()
else()
  foreach(t residfp sidplayfp miniaudio atariaudio xmp tfmxdec)
    target_compile_options(${t} PRIVATE -w)
  endforeach()
endif()
