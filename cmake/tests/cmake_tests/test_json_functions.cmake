include(cmake_test/cmake_test)
include(wares)

ct_add_test(NAME "_json_equals")
function(${_json_equals})
    json_equals("{\"name\": \"tom\", \"charisma\": 100000}" "{\"name\": \"tom\", \"charisma\": 100000}" equal)
    ct_assert_equal(${equal} TRUE)
endfunction()