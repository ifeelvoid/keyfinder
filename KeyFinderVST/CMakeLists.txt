cmake_minimum_required(VERSION 3.22)

# Builds the VST3 and AU analyzers with Command Line Tools only (no Xcode required).
#   cmake -S KeyFinderVST -B build-plugin -DKEYFINDER_JUCE_DIR=/path/to/JUCE
#   cmake --build build-plugin --config Release -j8
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Universal plugin binaries")
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Matches the desktop app floor")

project(KeyFinderVST VERSION 3.0.2 LANGUAGES C CXX)

set(KEYFINDER_JUCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../JUCE" CACHE PATH "JUCE 8 checkout")
if(NOT EXISTS "${KEYFINDER_JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "JUCE not found at ${KEYFINDER_JUCE_DIR}; pass -DKEYFINDER_JUCE_DIR=...")
endif()
add_subdirectory("${KEYFINDER_JUCE_DIR}" "${CMAKE_BINARY_DIR}/JUCE")

# Codes match the 2.0 release so hosts keep existing sessions; the AU type changes from
# instrument (aumu) to effect (aufx) because the plugin analyzes and passes audio through.
juce_add_plugin(KeyFinderVST
    COMPANY_NAME "IFEELVOID"
    PRODUCT_NAME "KeyFinderVST"
    BUNDLE_ID "com.ifeelvoid.keyfinder.plugin"
    PLUGIN_MANUFACTURER_CODE IFVO
    PLUGIN_CODE KFvs
    FORMATS VST3 AU
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    AU_MAIN_TYPE kAudioUnitType_Effect
    VST3_CATEGORIES Fx Analyzer
    COPY_PLUGIN_AFTER_BUILD FALSE)

juce_generate_juce_header(KeyFinderVST)

target_sources(KeyFinderVST PRIVATE
    Source/PluginProcessor.cpp
    Source/PluginEditor.cpp
    Source/KeyDetector.cpp
    Source/BPMDetector.cpp
    Source/AnalysisAudio.mm)

target_compile_features(KeyFinderVST PRIVATE cxx_std_17)
target_compile_definitions(KeyFinderVST PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries(KeyFinderVST
    PRIVATE
        juce::juce_audio_utils
        juce::juce_dsp
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

# Optional developer tool: compares the plugin detectors with the Swift engine on real files.
option(KEYFINDER_BUILD_PARITY_TOOL "Build the plugin/app detector parity CLI" OFF)
if(KEYFINDER_BUILD_PARITY_TOOL)
    juce_add_console_app(KeyFinderPluginParity PRODUCT_NAME "KeyFinderPluginParity")
    juce_generate_juce_header(KeyFinderPluginParity)
    target_sources(KeyFinderPluginParity PRIVATE
        Tools/PluginParity.cpp Source/KeyDetector.cpp Source/BPMDetector.cpp Source/AnalysisAudio.mm)
    target_compile_features(KeyFinderPluginParity PRIVATE cxx_std_17)
    target_compile_definitions(KeyFinderPluginParity PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
    target_link_libraries(KeyFinderPluginParity PRIVATE juce::juce_audio_utils juce::juce_dsp
        PUBLIC juce::juce_recommended_config_flags)

    # Hosts the built VST3 and checks effect registration and bit-exact pass-through.
    juce_add_console_app(KeyFinderPluginHostSmoke PRODUCT_NAME "KeyFinderPluginHostSmoke")
    target_sources(KeyFinderPluginHostSmoke PRIVATE Tools/PluginHostSmoke.cpp)
    juce_generate_juce_header(KeyFinderPluginHostSmoke)
    target_compile_features(KeyFinderPluginHostSmoke PRIVATE cxx_std_17)
    target_compile_definitions(KeyFinderPluginHostSmoke PRIVATE
        JUCE_PLUGINHOST_VST3=1 JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
    target_link_libraries(KeyFinderPluginHostSmoke PRIVATE juce::juce_audio_utils
        PUBLIC juce::juce_recommended_config_flags)

    juce_add_console_app(KeyFinderPluginRegression PRODUCT_NAME "KeyFinderPluginRegression")
    target_sources(KeyFinderPluginRegression PRIVATE Tools/PluginRegression.cpp)
    juce_generate_juce_header(KeyFinderPluginRegression)
    target_compile_features(KeyFinderPluginRegression PRIVATE cxx_std_17)
    target_compile_definitions(KeyFinderPluginRegression PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
    # Link production code without inheriting its plug-in-only JUCE_STANDALONE_APPLICATION define.
    add_dependencies(KeyFinderPluginRegression KeyFinderVST)
    target_link_libraries(KeyFinderPluginRegression PRIVATE "$<TARGET_FILE:KeyFinderVST>"
        juce::juce_audio_utils juce::juce_dsp "-framework AVFoundation"
        PUBLIC juce::juce_recommended_config_flags)

    # Renders the editor tabs to PNG for visual review against the desktop app.
    juce_add_console_app(KeyFinderPluginSnapshot PRODUCT_NAME "KeyFinderPluginSnapshot")
    target_sources(KeyFinderPluginSnapshot PRIVATE Tools/PluginSnapshot.cpp)
    juce_generate_juce_header(KeyFinderPluginSnapshot)
    target_compile_features(KeyFinderPluginSnapshot PRIVATE cxx_std_17)
    target_compile_definitions(KeyFinderPluginSnapshot PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
    add_dependencies(KeyFinderPluginSnapshot KeyFinderVST)
    target_link_libraries(KeyFinderPluginSnapshot PRIVATE "$<TARGET_FILE:KeyFinderVST>"
        juce::juce_audio_utils juce::juce_dsp "-framework AVFoundation"
        PUBLIC juce::juce_recommended_config_flags)
    enable_testing()
    add_test(NAME KeyFinderPluginRegression COMMAND KeyFinderPluginRegression)
    set_tests_properties(KeyFinderPluginRegression PROPERTIES TIMEOUT 90)
endif()

# AnalysisAudio.mm uses AVAudioConverter, matching the desktop app's audio preparation.
set_source_files_properties(Source/AnalysisAudio.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
foreach(target KeyFinderVST KeyFinderPluginParity)
    if(TARGET ${target})
        target_link_libraries(${target} PRIVATE "-framework AVFoundation")
    endif()
endforeach()
