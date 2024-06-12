# wares.cmake: a small package manager
cmake_minimum_required(VERSION 3.19 FATAL_ERROR)

# wares version
set(CURRENT_WARES_VERSION 0.0.1-alpha)

# Initialize logging prefix
if(NOT __WARES_INDENT)
  set(__WARES_INDENT
      "[wares]:"
      CACHE INTERNAL ""
  )
endif()

if(NOT COMMAND __wares_log)
  function(__wares_log)
    message("${WARES_INDENT} ${ARGV}")
  endfunction()
endif()

############################
# Helpful Macros
############################
macro(__set_bool var)
     if(${ARGN})
         set(${var} ON)
     else()
         set(${var} OFF)
     endif()
endmacro()

############################
# Private details
############################
#if(NOT WIN32)
  string(ASCII 27 Esc)
  set(ColourReset "${Esc}[m")
  set(ColourBold  "${Esc}[1m")
  set(Red         "${Esc}[31m")
  set(Green       "${Esc}[32m")
  set(Yellow      "${Esc}[33m")
  set(Blue        "${Esc}[34m")
  set(Magenta     "${Esc}[35m")
  set(Cyan        "${Esc}[36m")
  set(White       "${Esc}[37m")
  set(BoldRed     "${Esc}[1;31m")
  set(BoldGreen   "${Esc}[1;32m")
  set(BoldYellow  "${Esc}[1;33m")
  set(BoldBlue    "${Esc}[1;34m")
  set(BoldMagenta "${Esc}[1;35m")
  set(BoldCyan    "${Esc}[1;36m")
  set(BoldWhite   "${Esc}[1;37m")
#endif()

############################
# Providers
############################

# Github provider
function(wares_github_install DEPEDENCY)

endfunction()

# Path Provider

function(wares_path_install DEPENDENCY)
    string(JSON DEPENDENCY GET ${NAME} "name")
    string(JSON DEPENDENCY GET ${PATH} "path")

    # if there is a top-level CMakeLists.txt file, call add_subdirectory()
    if(EXISTS "${PATH}/CMakeLists.txt")
        add_subdirectory(${PATH})
    endif()

    # this should work for setting the source directory
    # TODO: set binary directory
    set("${NAME}_SOURCE_DIR" ${PATH})
    set("${NAME}_ADDED" YES)
endfunction()

function(__wares_parse_manifest FILENAME)
    file(READ ${FILENAME} MANIFEST_TEXT)
    #wares_log("${MANIFEST_TEXT}")
endfunction()

function(__wares_update)
    __wares_parse_manifest("${CMAKE_SOURCE_DIR}/wares.json")
endfunction()

function(__wares_install)
    file(READ "${CMAKE_SOURCE_DIR}/wares.lock" LOCKFILE_TEXT)
    string(JSON DEPENDENCIES_LIST GET ${LOCKFILE_TEXT} "dependencies")
    # when should the loop stop?
    string(JSON DEPENDENCIES_STOP LENGTH ${DEPENDENCIES_LIST})
    MATH(EXPR DEPENDENCIES_STOP "${DEPENDENCIES_STOP}-1")
    foreach(INDEX RANGE ${DEPENDENCIES_STOP})
        string(JSON DEPENDENCY GET ${DEPENDENCIES_LIST} ${INDEX})
        string(JSON PROVIDER_ID GET ${DEPENDENCY} "type")

        # call the correct provider implementation for install 
        if(NOT COMMAND "wares_${PROVIDER_ID}_install")
            __wares_log("No provider found for: ${PROVIDER_ID}")
        else()
           cmake_language(CALL "wares_${PROVIDER_ID}_install" "${DEPENDENCY}")
        endif()
    endforeach()
endfunction()

# The only command that needs to be run in CMakeLists.txt
# reponsible for updating the lockfile and downloading any missing dependencies
# after that, the important variables are defined similar to FetchContent and CPM.cmake
function(wares_sync)
    if(NOT EXISTS "${CMAKE_SOURCE_DIR}/wares.json")
        __wares_log("You must create a wares.json file!")
    endif()

    # if the lock file doesn't exist, then it needs updating
    __set_bool(B_UPDATE_LOCKFILE NOT EXISTS "${CMAKE_SOURCE_DIR}/wares.lock")
    if(NOT B_UPDATE_LOCKFILE)
        file(TIMESTAMP "${CMAKE_SOURCE_DIR}/wares.json" WARES_JSON_TS)
        file(TIMESTAMP "${CMAKE_SOURCE_DIR}/wares.lock" WARES_LOCK_TS)

        # comparing the timestamps as strings **seems** to work
        string(COMPARE LESS ${WARES_LOCK_TS} ${WARES_JSON_TS} B_UPDATE_LOCKFILE)
    endif()

    if(B_UPDATE_LOCKFILE)
        __wares_log("Updating lockfile...")
        __wares_update()
    endif()

    __wares_log("Checking lockfile...")
    __wares_install()
endfunction()

__wares_log("Wares v${CURRENT_WARES_VERSION} (cmake) loaded!")