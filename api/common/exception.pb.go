// Copyright © 2021 Luther Systems, Ltd. All right reserved.

// Code generated by protoc-gen-go. DO NOT EDIT.
// versions:
// 	protoc-gen-go v1.27.1
// 	protoc        (unknown)
// source: common/exception.proto

package common

import (
	protoreflect "google.golang.org/protobuf/reflect/protoreflect"
	protoimpl "google.golang.org/protobuf/runtime/protoimpl"
	reflect "reflect"
	sync "sync"
)

const (
	// Verify that this generated code is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(20 - protoimpl.MinVersion)
	// Verify that runtime/protoimpl is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(protoimpl.MaxVersion - 20)
)

// Type of exception.
type Exception_Type int32

const (
	// Default for no exception.
	Exception_INVALID_TYPE Exception_Type = 0
	// Business logic error.
	Exception_BUSINESS Exception_Type = 1
	// A service was unavailable.
	Exception_SERVICE_NOT_AVAILABLE Exception_Type = 2
	// Infrastructure was down.
	Exception_INFRASTRUCTURE Exception_Type = 3
	// Catch-all for all other types.
	Exception_UNEXPECTED Exception_Type = 4
	// Security related error.
	Exception_SECURITY_VIOLATION Exception_Type = 5
)

// Enum value maps for Exception_Type.
var (
	Exception_Type_name = map[int32]string{
		0: "INVALID_TYPE",
		1: "BUSINESS",
		2: "SERVICE_NOT_AVAILABLE",
		3: "INFRASTRUCTURE",
		4: "UNEXPECTED",
		5: "SECURITY_VIOLATION",
	}
	Exception_Type_value = map[string]int32{
		"INVALID_TYPE":          0,
		"BUSINESS":              1,
		"SERVICE_NOT_AVAILABLE": 2,
		"INFRASTRUCTURE":        3,
		"UNEXPECTED":            4,
		"SECURITY_VIOLATION":    5,
	}
)

func (x Exception_Type) Enum() *Exception_Type {
	p := new(Exception_Type)
	*p = x
	return p
}

func (x Exception_Type) String() string {
	return protoimpl.X.EnumStringOf(x.Descriptor(), protoreflect.EnumNumber(x))
}

func (Exception_Type) Descriptor() protoreflect.EnumDescriptor {
	return file_common_exception_proto_enumTypes[0].Descriptor()
}

func (Exception_Type) Type() protoreflect.EnumType {
	return &file_common_exception_proto_enumTypes[0]
}

func (x Exception_Type) Number() protoreflect.EnumNumber {
	return protoreflect.EnumNumber(x)
}

// Deprecated: Use Exception_Type.Descriptor instead.
func (Exception_Type) EnumDescriptor() ([]byte, []int) {
	return file_common_exception_proto_rawDescGZIP(), []int{0, 0}
}

// General message for exceptions.
type Exception struct {
	state         protoimpl.MessageState
	sizeCache     protoimpl.SizeCache
	unknownFields protoimpl.UnknownFields

	// UUID for exception.
	Id string `protobuf:"bytes,1,opt,name=id,proto3" json:"id,omitempty"`
	// Type of exception.
	Type Exception_Type `protobuf:"varint,2,opt,name=type,proto3,enum=common.Exception_Type" json:"type,omitempty"`
	// Timestamp for when the exception occurred (RFC3339).
	Timestamp string `protobuf:"bytes,3,opt,name=timestamp,proto3" json:"timestamp,omitempty"`
	// Human readable description of exception.
	Description string `protobuf:"bytes,4,opt,name=description,proto3" json:"description,omitempty"`
	// Additional metadata about the exception.
	ExceptionMetadata map[string]string `protobuf:"bytes,5,rep,name=exception_metadata,json=exceptionMetadata,proto3" json:"exception_metadata,omitempty" protobuf_key:"bytes,1,opt,name=key,proto3" protobuf_val:"bytes,2,opt,name=value,proto3"`
}

func (x *Exception) Reset() {
	*x = Exception{}
	if protoimpl.UnsafeEnabled {
		mi := &file_common_exception_proto_msgTypes[0]
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		ms.StoreMessageInfo(mi)
	}
}

func (x *Exception) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*Exception) ProtoMessage() {}

func (x *Exception) ProtoReflect() protoreflect.Message {
	mi := &file_common_exception_proto_msgTypes[0]
	if protoimpl.UnsafeEnabled && x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use Exception.ProtoReflect.Descriptor instead.
func (*Exception) Descriptor() ([]byte, []int) {
	return file_common_exception_proto_rawDescGZIP(), []int{0}
}

func (x *Exception) GetId() string {
	if x != nil {
		return x.Id
	}
	return ""
}

func (x *Exception) GetType() Exception_Type {
	if x != nil {
		return x.Type
	}
	return Exception_INVALID_TYPE
}

func (x *Exception) GetTimestamp() string {
	if x != nil {
		return x.Timestamp
	}
	return ""
}

func (x *Exception) GetDescription() string {
	if x != nil {
		return x.Description
	}
	return ""
}

func (x *Exception) GetExceptionMetadata() map[string]string {
	if x != nil {
		return x.ExceptionMetadata
	}
	return nil
}

// Exception messages.
type ExceptionResponse struct {
	state         protoimpl.MessageState
	sizeCache     protoimpl.SizeCache
	unknownFields protoimpl.UnknownFields

	// An exception if an error occurred during processing request.
	Exception *Exception `protobuf:"bytes,1,opt,name=exception,proto3" json:"exception,omitempty"`
}

func (x *ExceptionResponse) Reset() {
	*x = ExceptionResponse{}
	if protoimpl.UnsafeEnabled {
		mi := &file_common_exception_proto_msgTypes[1]
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		ms.StoreMessageInfo(mi)
	}
}

func (x *ExceptionResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*ExceptionResponse) ProtoMessage() {}

func (x *ExceptionResponse) ProtoReflect() protoreflect.Message {
	mi := &file_common_exception_proto_msgTypes[1]
	if protoimpl.UnsafeEnabled && x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use ExceptionResponse.ProtoReflect.Descriptor instead.
func (*ExceptionResponse) Descriptor() ([]byte, []int) {
	return file_common_exception_proto_rawDescGZIP(), []int{1}
}

func (x *ExceptionResponse) GetException() *Exception {
	if x != nil {
		return x.Exception
	}
	return nil
}

var File_common_exception_proto protoreflect.FileDescriptor

var file_common_exception_proto_rawDesc = []byte{
	0x0a, 0x16, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x2f, 0x65, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69,
	0x6f, 0x6e, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12, 0x06, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e,
	0x22, 0xa5, 0x03, 0x0a, 0x09, 0x45, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x0e,
	0x0a, 0x02, 0x69, 0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x02, 0x69, 0x64, 0x12, 0x2a,
	0x0a, 0x04, 0x74, 0x79, 0x70, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x0e, 0x32, 0x16, 0x2e, 0x63,
	0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x2e, 0x45, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x2e,
	0x54, 0x79, 0x70, 0x65, 0x52, 0x04, 0x74, 0x79, 0x70, 0x65, 0x12, 0x1c, 0x0a, 0x09, 0x74, 0x69,
	0x6d, 0x65, 0x73, 0x74, 0x61, 0x6d, 0x70, 0x18, 0x03, 0x20, 0x01, 0x28, 0x09, 0x52, 0x09, 0x74,
	0x69, 0x6d, 0x65, 0x73, 0x74, 0x61, 0x6d, 0x70, 0x12, 0x20, 0x0a, 0x0b, 0x64, 0x65, 0x73, 0x63,
	0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x04, 0x20, 0x01, 0x28, 0x09, 0x52, 0x0b, 0x64,
	0x65, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x12, 0x57, 0x0a, 0x12, 0x65, 0x78,
	0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x5f, 0x6d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61,
	0x18, 0x05, 0x20, 0x03, 0x28, 0x0b, 0x32, 0x28, 0x2e, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x2e,
	0x45, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x2e, 0x45, 0x78, 0x63, 0x65, 0x70, 0x74,
	0x69, 0x6f, 0x6e, 0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x45, 0x6e, 0x74, 0x72, 0x79,
	0x52, 0x11, 0x65, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x4d, 0x65, 0x74, 0x61, 0x64,
	0x61, 0x74, 0x61, 0x1a, 0x44, 0x0a, 0x16, 0x45, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e,
	0x4d, 0x65, 0x74, 0x61, 0x64, 0x61, 0x74, 0x61, 0x45, 0x6e, 0x74, 0x72, 0x79, 0x12, 0x10, 0x0a,
	0x03, 0x6b, 0x65, 0x79, 0x18, 0x01, 0x20, 0x01, 0x28, 0x09, 0x52, 0x03, 0x6b, 0x65, 0x79, 0x12,
	0x14, 0x0a, 0x05, 0x76, 0x61, 0x6c, 0x75, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28, 0x09, 0x52, 0x05,
	0x76, 0x61, 0x6c, 0x75, 0x65, 0x3a, 0x02, 0x38, 0x01, 0x22, 0x7d, 0x0a, 0x04, 0x54, 0x79, 0x70,
	0x65, 0x12, 0x10, 0x0a, 0x0c, 0x49, 0x4e, 0x56, 0x41, 0x4c, 0x49, 0x44, 0x5f, 0x54, 0x59, 0x50,
	0x45, 0x10, 0x00, 0x12, 0x0c, 0x0a, 0x08, 0x42, 0x55, 0x53, 0x49, 0x4e, 0x45, 0x53, 0x53, 0x10,
	0x01, 0x12, 0x19, 0x0a, 0x15, 0x53, 0x45, 0x52, 0x56, 0x49, 0x43, 0x45, 0x5f, 0x4e, 0x4f, 0x54,
	0x5f, 0x41, 0x56, 0x41, 0x49, 0x4c, 0x41, 0x42, 0x4c, 0x45, 0x10, 0x02, 0x12, 0x12, 0x0a, 0x0e,
	0x49, 0x4e, 0x46, 0x52, 0x41, 0x53, 0x54, 0x52, 0x55, 0x43, 0x54, 0x55, 0x52, 0x45, 0x10, 0x03,
	0x12, 0x0e, 0x0a, 0x0a, 0x55, 0x4e, 0x45, 0x58, 0x50, 0x45, 0x43, 0x54, 0x45, 0x44, 0x10, 0x04,
	0x12, 0x16, 0x0a, 0x12, 0x53, 0x45, 0x43, 0x55, 0x52, 0x49, 0x54, 0x59, 0x5f, 0x56, 0x49, 0x4f,
	0x4c, 0x41, 0x54, 0x49, 0x4f, 0x4e, 0x10, 0x05, 0x22, 0x44, 0x0a, 0x11, 0x45, 0x78, 0x63, 0x65,
	0x70, 0x74, 0x69, 0x6f, 0x6e, 0x52, 0x65, 0x73, 0x70, 0x6f, 0x6e, 0x73, 0x65, 0x12, 0x2f, 0x0a,
	0x09, 0x65, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x18, 0x01, 0x20, 0x01, 0x28, 0x0b,
	0x32, 0x11, 0x2e, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x2e, 0x45, 0x78, 0x63, 0x65, 0x70, 0x74,
	0x69, 0x6f, 0x6e, 0x52, 0x09, 0x65, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6f, 0x6e, 0x42, 0x5b,
	0x0a, 0x18, 0x63, 0x6f, 0x6d, 0x2e, 0x6c, 0x75, 0x74, 0x68, 0x65, 0x72, 0x73, 0x79, 0x73, 0x74,
	0x65, 0x6d, 0x73, 0x2e, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x42, 0x0e, 0x45, 0x78, 0x63, 0x65,
	0x70, 0x74, 0x69, 0x6f, 0x6e, 0x50, 0x72, 0x6f, 0x74, 0x6f, 0x50, 0x01, 0x5a, 0x2d, 0x67, 0x69,
	0x74, 0x68, 0x75, 0x62, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x6c, 0x75, 0x74, 0x68, 0x65, 0x72, 0x73,
	0x79, 0x73, 0x74, 0x65, 0x6d, 0x73, 0x2f, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x73, 0x2f, 0x63, 0x6f,
	0x6d, 0x6d, 0x6f, 0x6e, 0x3b, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x62, 0x06, 0x70, 0x72, 0x6f,
	0x74, 0x6f, 0x33,
}

var (
	file_common_exception_proto_rawDescOnce sync.Once
	file_common_exception_proto_rawDescData = file_common_exception_proto_rawDesc
)

func file_common_exception_proto_rawDescGZIP() []byte {
	file_common_exception_proto_rawDescOnce.Do(func() {
		file_common_exception_proto_rawDescData = protoimpl.X.CompressGZIP(file_common_exception_proto_rawDescData)
	})
	return file_common_exception_proto_rawDescData
}

var file_common_exception_proto_enumTypes = make([]protoimpl.EnumInfo, 1)
var file_common_exception_proto_msgTypes = make([]protoimpl.MessageInfo, 3)
var file_common_exception_proto_goTypes = []interface{}{
	(Exception_Type)(0),       // 0: common.Exception.Type
	(*Exception)(nil),         // 1: common.Exception
	(*ExceptionResponse)(nil), // 2: common.ExceptionResponse
	nil,                       // 3: common.Exception.ExceptionMetadataEntry
}
var file_common_exception_proto_depIdxs = []int32{
	0, // 0: common.Exception.type:type_name -> common.Exception.Type
	3, // 1: common.Exception.exception_metadata:type_name -> common.Exception.ExceptionMetadataEntry
	1, // 2: common.ExceptionResponse.exception:type_name -> common.Exception
	3, // [3:3] is the sub-list for method output_type
	3, // [3:3] is the sub-list for method input_type
	3, // [3:3] is the sub-list for extension type_name
	3, // [3:3] is the sub-list for extension extendee
	0, // [0:3] is the sub-list for field type_name
}

func init() { file_common_exception_proto_init() }
func file_common_exception_proto_init() {
	if File_common_exception_proto != nil {
		return
	}
	if !protoimpl.UnsafeEnabled {
		file_common_exception_proto_msgTypes[0].Exporter = func(v interface{}, i int) interface{} {
			switch v := v.(*Exception); i {
			case 0:
				return &v.state
			case 1:
				return &v.sizeCache
			case 2:
				return &v.unknownFields
			default:
				return nil
			}
		}
		file_common_exception_proto_msgTypes[1].Exporter = func(v interface{}, i int) interface{} {
			switch v := v.(*ExceptionResponse); i {
			case 0:
				return &v.state
			case 1:
				return &v.sizeCache
			case 2:
				return &v.unknownFields
			default:
				return nil
			}
		}
	}
	type x struct{}
	out := protoimpl.TypeBuilder{
		File: protoimpl.DescBuilder{
			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
			RawDescriptor: file_common_exception_proto_rawDesc,
			NumEnums:      1,
			NumMessages:   3,
			NumExtensions: 0,
			NumServices:   0,
		},
		GoTypes:           file_common_exception_proto_goTypes,
		DependencyIndexes: file_common_exception_proto_depIdxs,
		EnumInfos:         file_common_exception_proto_enumTypes,
		MessageInfos:      file_common_exception_proto_msgTypes,
	}.Build()
	File_common_exception_proto = out.File
	file_common_exception_proto_rawDesc = nil
	file_common_exception_proto_goTypes = nil
	file_common_exception_proto_depIdxs = nil
}