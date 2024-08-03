# wares.cmake: a small package manager
cmake_minimum_required(VERSION 3.19 FATAL_ERROR)

# wares version
set(CURRENT_WARES_VERSION 0.0.1-alpha)

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

# Initialize logging prefix
if(NOT __WARES_INDENT)
  set(__WARES_INDENT
      "wares:"
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
# Helpful Functions
############################

# inverts a boolean value
function (invert_bool bool result)
  if(${bool})
    set(${result} false PARENT_SCOPE)
  else()
    set(${result} true PARENT_SCOPE)
  endif()
endfunction()

#------
# JSON
#------

# returns true if the two elements are not equal
function(json_nequals left right result)
    string(JSON equal EQUAL ${left} ${right})
    invert_bool(${equal} ${not_equal})
    set(${result} ${not_equal} PARENT_SCOPE)
endfunction()

# json_arr_len really isn't a good name because it returns the array length - 1, perfect for a 
# foreach loop
# returns the length of a json array
function(json_arr_len arr result)
    string(JSON len LENGTH ${arr})
    math(EXPR len "${len}-1")
    set(${result} ${len} PARENT_SCOPE)
endfunction()

# takes a json obj, array, and outvar and sets out var to true if the object doesn't exist in the array.
function(json_obj_is_unique json_array json_object result)
    set(unique TRUE)
    
    # loop through the array
    json_arr_len(json_array array_length)
    foreach(index RANGE ${array_length})
        # get the element at that index
        string(JSON element GET ${json_array} ${index})

        # compare the two elements
        json_nequals(${element} ${json_object} unique)
        
        if(NOT ${unique})
            break()
        endif()
    endforeach()
    set(${result} ${found} PARENT_SCOPE)
endfunction()

#---------
# Version
#---------

function(make_version result major minor patch prerelease build)
endfunction()

# CACHE_DIR
# Unfortunately, cmake's cache variable system is a little weird,
# meaning that if a user wants to change the cache directory, they 
# need to reconfigure the whole project.

# First used the cache value,
# Then use the environment variable value
# Then use a default

# It is defined in the environment, but it is not defined in the cache
if(DEFINED ENV{WARES_CACHE} AND NOT DEFINED CACHE{WARES_CACHE})
    # Set to Environment Value
    set(WARES_CACHE $ENV{WARES_CACHE} CACHE STRING "Wares' cache directory")
endif()

# It is still not defined in the cache, set a default
if (NOT DEFINED CACHE{WARES_CACHE})
    # Set Default Value
    set(WARES_CACHE "${CMAKE_SOURCE_DIR}/PackageCache" CACHE STRING "Wares' cache directory")
endif()

__wares_log("Wares cache: ${WARES_CACHE}")

############################
# Providers
############################

# Github provider
function(wares_gh_update DEPENDENCY)
    message("Github: ${DEPENDENCY}")
    set(lock_info_array "[]")
    return(PROPOGATE lock_info_array)
endfunction()

function(wares_gh_install DEPENDENCY)
    message("Github: ${DEPENDENCY}")
endfunction()

function(wares_github_update DEPENDENCY)
    wares_gh_update(${DEPENDENCY})
endfunction()

function(wares_github_install DEPENDENCY)
    wares_gh_install(${DEPENDENCY})
    return(PROPOGATE lock_info_array)
endfunction()

# Path Provider
function(wares_path_update DEP_INFO)
    string(JSON dep_type TYPE ${DEP_INFO})

    string(JSON lock_info SET "{}" "type" "\"path\"")

    if(${dep_type} STREQUAL "STRING")
        # path is just the dep_info string
        string(JSON lock_info SET ${lock_info} "path" ${DEP_INFO})
        # TODO: update the following regex to support ending slashes.
        string(REGEX MATCH "[0-9a-zA-Z_\.\- ]+$" name)
        string(JSON lock_info SET ${lock_info} "name" "\"${name}\"")
    elseif(${dep_type} STREQUAL "OBJECT")
        # an object is easy, just copy the information
        string(JSON path GET ${DEP_INFO} "path")
        string(JSON lock_info SET ${lock_info} "path" "\"${path}\"")

        string(JSON name GET ${DEP_INFO} "name")
        string(JSON lock_info SET ${lock_info} "name" "\"${name}\"")
    endif()

    # check the path for sub-manifest files
    string(JSON path GET ${lock_info} "path")

    if(EXISTS "${path}/wares.json")
        __wares_parse_manifest("${path}/wares.json")
        set(lock_info_array ${deps_lock_array})
    else()
        set(lock_info_array "[]")
    endif()

    message(${deps_lock_array})

    string(JSON ${lock_info_array_len} LENGTH ${lock_info_array})
    string(JSON ${lock_info_array} SET ${lock_info_array} ${lock_info_array_len} ${lock_info})
    
    message(${deps_lock_array})

    return(PROPOGATE lock_info_array)
endfunction()

function(wares_path_install DEPENDENCY)
    string(JSON NAME GET ${DEPENDENCY} "name")
    string(JSON PATH GET ${DEPENDENCY} "path")

    # if there is a top-level CMakeLists.txt file, call add_subdirectory()
    # the binary directory should be something like:
    # out_dir/deps/
    # TODO: move out to the wares_sync command
    if(EXISTS "${PATH}/CMakeLists.txt")
        add_subdirectory(${PATH} "./deps/${NAME}")
        set("${NAME}_BINARY_DIR" "${CMAKE_BINARY_DIR}/deps/${NAME}")
    endif()

    # this should work for setting the source directory
    # TODO: set binary directory
    set("${NAME}_SOURCE_DIR" ${PATH})
    set("${NAME}_ADDED" YES)
endfunction()

function(__wares_parse_manifest FILENAME)
    file(READ ${FILENAME} manifest_text)
    string(JSON manifest_dependencies GET ${manifest_text} "dependencies")
    string(JSON manifest_dependencies_stop LENGTH ${manifest_dependencies})
    math(EXPR manifest_dependencies_stop "${manifest_dependencies_stop}-1")
    
    set(deps_lock_array "[]")
    # loop through the dependencies array
    foreach(index RANGE ${manifest_dependencies_stop})
        string(JSON dependency_type TYPE ${manifest_dependencies} ${index})
        string(JSON dependency GET ${manifest_dependencies} ${index})
        if(${dependency_type} STREQUAL "STRING")
            string(REGEX MATCH "^[A-Za-z]+" dependency_provider_id ${dependency})
            
            # strip the beginning of the string to remove the provider id
            string(LENGTH ${dependency_provider_id} provider_id_length)
            math(EXPR provider_id_length "${provider_id_length} + 1")
            string(SUBSTRING ${dependency} ${provider_id_length} -1 provider_args)

            # call the correct provider implementation for install 
            if(NOT COMMAND "wares_${dependency_provider_id}_update")
                __wares_log("No provider found for: ${dependency_provider_id}")
            else()
                cmake_language(CALL "wares_${dependency_provider_id}_update" ${provider_args})
            endif()
        elseif(${dependency_type} STREQUAL "OBJECT")
            # easy case: get the provider id and look it up
            string(JSON dependency_provider_id GET ${dependency} "type")
            
            # call the correct provider implementation for install 
            if(NOT COMMAND "wares_${dependency_provider_id}_update")
                __wares_log("No provider found for: ${dependency_provider_id}")
            else()
                cmake_language(CALL "wares_${dependency_provider_id}_update" ${dependency})
            endif()
        else()
            __wares_log("Dependency must either be a string or a json object")
        endif()

        # join the new lock info (if it is unique)
        # loop through the new lock_info_array
        message("${lock_info_array}")
        json_arr_len(${lock_info_array} lock_info_array_stop)
        foreach(jindex RANGE ${lock_info_array_stop})
            # if not found in the original deps_lock_array, add it
            json_obj_is_unique(${element} ${deps_lock_array} element_unique)
            if(${element_unique})
                string(JSON deps_lock_array_len LENGTH ${deps_lock_array})
                string(JSON deps_lock_array SET ${deps_lock_array} ${deps_lock_array_len} ${element})  
            endif()
        endforeach()
    endforeach()

    return(PROPAGATE deps_lock_array)
endfunction()

function(__wares_update)
    __wares_parse_manifest("${CMAKE_SOURCE_DIR}/wares.json")

    string(JSON lockfile_data SET "{}" "version" 0)
    string(JSON lockfile_data SET ${lockfile_data} "dependencies" ${deps_lock_array})
    file(WRITE "wares.lock-test" ${lockfile_data})
endfunction()

# reads the lockfile and calls each provider with the dependency information
# in order to install it.
function(__wares_install)
    file(READ "${CMAKE_SOURCE_DIR}/wares.lock" LOCKFILE_TEXT)
    string(JSON DEPENDENCIES_LIST GET ${LOCKFILE_TEXT} "dependencies")
    # when should the loop stop?
    string(JSON DEPENDENCIES_STOP LENGTH ${DEPENDENCIES_LIST})
    math(EXPR DEPENDENCIES_STOP "${DEPENDENCIES_STOP}-1")
    foreach(INDEX RANGE ${DEPENDENCIES_STOP})
        string(JSON DEPENDENCY GET ${DEPENDENCIES_LIST} ${INDEX})
        string(JSON PROVIDER_ID GET ${DEPENDENCY} "type")

        # call the correct provider implementation for install 
        if(NOT COMMAND "wares_${PROVIDER_ID}_install")
            __wares_log("No provider found for: ${PROVIDER_ID}")
        else()
           cmake_language(CALL "wares_${PROVIDER_ID}_install" ${DEPENDENCY})
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
    # TODO: loop through all dependencies and check for CMakeLists.txt files
endfunction()

# custom commands

# wares clean

# wares sync

__wares_log("Wares v${CURRENT_WARES_VERSION} (cmake) loaded!")