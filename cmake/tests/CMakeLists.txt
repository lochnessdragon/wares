cmake_minimum_required(VERSION 3.19)
project(WaresTests)

include(CTest)

# dependency versions
set(CMAKEPP_LANG_VERSION v1.0.0)
set(CMAIZE_VERSION v0.2.1)

#[[[
# This function encapsulates the process of getting CMakeTest using CMake's
# FetchContent module. We have encapsulated it in a function so we can set
# the options for its configure step without affecting the options for the
# parent project's configure step (namely we do not want to build CMakeTest's
# unit tests).
# from: https://github.com/CMakePP/CMakeTest
#]]
macro(get_cmake_test)
    include(cmake_test/cmake_test OPTIONAL RESULT_VARIABLE cmake_test_found)
    if(NOT cmake_test_found)
        # Store whether we are building tests or not, then turn off the tests
        set(build_testing_old "${BUILD_TESTING}")
        set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
        # Download CMakeTest and bring it into scope
        include(FetchContent)
        FetchContent_Declare(
             cmake_test
             GIT_REPOSITORY https://github.com/CMakePP/CMakeTest
       )
       FetchContent_MakeAvailable(cmake_test)

       # Restore the previous value
       set(BUILD_TESTING "${build_testing_old}" CACHE BOOL "" FORCE)
    endif()
endmacro()

#[[
# This function encapsulates the process of getting CMakePP using CMake's
# FetchContent module. We have encapsulated it in a function so we can set
# the options for its configure step without affecting the options for the
# parent project's configure step (namely we do not want to build CMakePP's
# unit tests).
#]]
function(get_cmaize)
    include(cmaize/cmaize OPTIONAL RESULT_VARIABLE cmaize_found)
    if(NOT cmaize_found)
        # Store whether we are building tests or not, then turn off the tests
        set(build_testing_old "${BUILD_TESTING}")
        set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
        # Download CMakePP and bring it into scope
        include(FetchContent)
        FetchContent_Declare(
            cmaize
            GIT_REPOSITORY https://github.com/CMakePP/CMaize
            GIT_TAG ${CMAIZE_VERSION}
        )
        FetchContent_MakeAvailable(cmaize)

        set(
            CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" "${cmake_test_SOURCE_DIR}/cmake"
            PARENT_SCOPE
        )

        # Restore the previous value
        set(BUILD_TESTING "${build_testing_old}" CACHE BOOL "" FORCE)
    endif()
endfunction()

#[[
# This function encapsulates the process of getting CMakePPLang using CMake's
# FetchContent module. When CMaize supports find_or_build for CMake modules this
# file will be deprecated.
#]]
function(get_cmakepp_lang)
    include(
        cmakepp_lang/cmakepp_lang
        OPTIONAL
        RESULT_VARIABLE cmakepp_lang_found
    )
    if(NOT cmakepp_lang_found)
        # Store whether we are building tests or not, then turn off the tests
        set(build_testing_old "${BUILD_TESTING}")
        set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
        # Download CMakePP and bring it into scope
        include(FetchContent)
        FetchContent_Declare(
            cmakepp_lang
            GIT_REPOSITORY https://github.com/CMakePP/CMakePPLang
            GIT_TAG ${CMAKEPP_LANG_VERSION}
        )
        FetchContent_MakeAvailable(cmakepp_lang)

        set(
            CMAKE_MODULE_PATH
            "${CMAKE_MODULE_PATH}" "${cmakepp_lang_SOURCE_DIR}/cmake"
            PARENT_SCOPE
        )

        # Restore the previous value
        set(BUILD_TESTING "${build_testing_old}" CACHE BOOL "" FORCE)
    endif()
endfunction()

# Call the function we just wrote to get CMakeTest
get_cmaize()
get_cmakepp_lang()
get_cmake_test()

# Include CMakeTest
#include(${cmake_test_SOURCE_DIR}/cmake/get_cmaize.cmake)
#include(${cmake_test_SOURCE_DIR}/cmake/get_cmakepp_lang.cmake)
#list(APPEND CMAKE_MODULE_PATH "${cmaize_SOURCE_DIR}/cmake" "${cmakepp_SOURCE_DIR}/cmake")
include(cmake_test/cmake_test)

# custom:

include(../wares.cmake)

ct_add_dir("./cmake_tests", CT_DEBUG_MODE_ON)