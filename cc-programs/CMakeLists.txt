# C++ benchmark programs, one executable per *.cc, built by
# scripts/build_version.sh against the libmata of one revision
# (CMAKE_PREFIX_PATH), with the same flags as the .emp interpreter.
cmake_minimum_required(VERSION 3.20)
project(cc-programs CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_library(LIBMATA mata REQUIRED NO_DEFAULT_PATH PATHS ${CMAKE_PREFIX_PATH} PATH_SUFFIXES lib lib64)
find_path(MATA_INCLUDE_DIR NAMES mata/nfa/nfa.hh REQUIRED NO_DEFAULT_PATH PATHS ${CMAKE_PREFIX_PATH} PATH_SUFFIXES include)
# bench.hh and mata_load.hh, shared with the .emp interpreter.
set(HARNESS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../harnesses/automata-program-parser/src/cpp)

file(GLOB programs CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/*.cc)
foreach(source ${programs})
    get_filename_component(name ${source} NAME_WE)
    add_executable(${name} ${source})
    target_include_directories(${name} PRIVATE ${MATA_INCLUDE_DIR} ${HARNESS_DIR})
    target_link_libraries(${name} PRIVATE ${LIBMATA})
endforeach()
