cmake_minimum_required(VERSION 3.16)
project(godot-nexus-coda LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
	message(
		WARNING
			"Use Clang (clang++ / clang-cl) for conformance; detected ${CMAKE_CXX_COMPILER_ID}. "
			"Example: cmake -B build -DCMAKE_CXX_COMPILER=clang++")
endif()

add_subdirectory(thirdparty/Catch2 EXCLUDE_FROM_ALL)

add_executable(nexus_coda_unit_tests tests/smoke_test.cpp)
target_link_libraries(nexus_coda_unit_tests PRIVATE Catch2::Catch2WithMain)
target_compile_options(
	nexus_coda_unit_tests
	PRIVATE
		$<$<OR:$<CXX_COMPILER_ID:Clang>,$<CXX_COMPILER_ID:AppleClang>>:-Wall -Wextra -Wpedantic>)

include(CTest)
add_test(NAME nexus_coda_unit COMMAND nexus_coda_unit_tests)
