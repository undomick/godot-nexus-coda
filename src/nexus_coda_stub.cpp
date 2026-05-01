#include "nexus_coda_stub.h"

#include <godot_cpp/core/class_db.hpp>

void NexusCodaStub::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_version"), &NexusCodaStub::get_version);
}

String NexusCodaStub::get_version() const {
	return "0.1.0";
}
