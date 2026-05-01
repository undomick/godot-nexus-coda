#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

class NexusCodaStub : public RefCounted {
	GDCLASS(NexusCodaStub, RefCounted);

protected:
	static void _bind_methods();

public:
	String get_version() const;
};
