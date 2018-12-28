#include "idl_defines.h"
#ifdef TAO_IDL_HAS_ANNOTATIONS

#include <string>
#include <list>

#include "be_extern.h"
#include "ast_structure.h"
#include "ast_field.h"
#include "utl_identifier.h"
#include "ast_union.h"
#include "ast_array.h"

#include "sample_keys.h"

static const char* root_type_to_string(SampleKeys::RootType root_type)
{
  switch (root_type) {
  case SampleKeys::PrimitiveType:
    return "PrimitiveType";
  case SampleKeys::StructureType:
    return "StructureType";
  case SampleKeys::UnionType:
    return "UnionType";
  case SampleKeys::ArrayType:
    return "ArrayType";
  default:
    return "InvalidType";
  }
}

SampleKeys::RootType SampleKeys::root_type(AST_Type* type)
{
  if (!type) {
    return InvalidType;
  }
  switch (type->unaliased_type()->node_type()) {
  case AST_Decl::NT_pre_defined:
  case AST_Decl::NT_string:
  case AST_Decl::NT_wstring:
  case AST_Decl::NT_enum:
    return PrimitiveType;
  case AST_Decl::NT_struct:
    return StructureType;
  case AST_Decl::NT_union:
    return UnionType;
  case AST_Decl::NT_array:
    return ArrayType;
  default:
    return InvalidType;
  }
}

SampleKeys::Error::Error()
{
}

SampleKeys::Error::Error(const SampleKeys::Error& error)
  : message_(error.message_)
{
}

SampleKeys::Error::Error(const std::string& message)
  : message_(message)
{
}

SampleKeys::Error::Error(AST_Decl* node, const std::string& message)
{
  std::stringstream ss;
  if (node) {
    ss
      << "Error on line " << node->line() << " in "
      << node->file_name() << ": ";
  }
  ss << message;
  message_ = ss.str();
}

SampleKeys::Error& SampleKeys::Error::operator=(const SampleKeys::Error& error)
{
  message_ = error.message_;
  return *this;
}

const char* SampleKeys::Error::what() const noexcept
{
  return message_.c_str();
}

SampleKeys::Iterator::Iterator()
  : pos_(0),
    child_(0),
    current_value_(0),
    root_(0),
    root_type_(InvalidType),
    parents_root_type_(SampleKeys::InvalidType),
    level_(0)
{
}

SampleKeys::Iterator::Iterator(SampleKeys& parent)
  : pos_(0),
    child_(0),
    current_value_(0),
    parents_root_type_(SampleKeys::InvalidType),
    level_(0)
{
  root_ = parent.root();
  root_type_ = parent.root_type();
  (*this)++;
}

SampleKeys::Iterator::Iterator(AST_Type* root, const Iterator& parent)
  : pos_(0),
    child_(0),
    current_value_(0),
    parents_root_type_(parent.root_type()),
    level_(parent.level() + 1)
{
  root_type_ = SampleKeys::root_type(root);
  root_ = root;
  (*this)++;
}

SampleKeys::Iterator::Iterator(AST_Field* root, const Iterator& parent)
  : pos_(0),
    child_(0),
    current_value_(0),
    parents_root_type_(parent.root_type()),
    level_(parent.level() + 1)
{
  AST_Type* type = root->field_type()->unaliased_type();
  root_type_ = SampleKeys::root_type(type);
  if (root_type_ == PrimitiveType) {
    root_ = root;
  } else {
    root_ = type;
  }
  (*this)++;
}

SampleKeys::Iterator::Iterator(const SampleKeys::Iterator& other)
  : pos_(0),
    child_(0),
    current_value_(0),
    root_(0),
    root_type_(InvalidType),
    level_(0)
{
  *this = other;
}

SampleKeys::Iterator::~Iterator()
{
  cleanup();
}

SampleKeys::Iterator& SampleKeys::Iterator::operator=(const SampleKeys::Iterator& other)
{
  cleanup();
  pos_ = other.pos_;
  current_value_ = other.current_value_;
  root_ = other.root_;
  root_type_ = other.root_type_;
  parents_root_type_ = other.parents_root_type_;
  level_ = other.level_;
  child_ = other.child_ ? new Iterator(*other.child_) : 0;
  return *this;
}

SampleKeys::Iterator& SampleKeys::Iterator::operator++()
{
  // Nop if we are a invalid iterator of any type
  if (!root_ || root_type_ == InvalidType) {
    return *this;
  }

  // If we have a child iterator, ask it for the next value
  if (child_) {
    Iterator& child = *child_;
    ++child;
    if (child == Iterator()) {
      delete child_;
      child_ = 0;
      pos_++;
    } else {
      current_value_ = *child;
      return *this;
    }
  }

  // If we are a structure, look for key fields
  if (root_type_ == StructureType) {
    AST_Structure* struct_root = dynamic_cast<AST_Structure*>(root_);
    size_t field_count = struct_root->nfields();
    for (; pos_ < field_count; ++pos_) {
      AST_Field** field_ptrptr;
      struct_root->field(field_ptrptr, pos_);
      AST_Field* field = *field_ptrptr;
      if (be_global->is_key(field)) {
        child_ = new Iterator(field, *this);
        Iterator& child = *child_;
        if (child == Iterator()) {
          delete child_;
          child_ = 0;
          throw Error(field, "field is marked as key, but does not contain any keys.");
        } else {
          current_value_ = *child;
          return *this;
        }
      }
    }

  // If we are an array, use the base type and repeat for every element
  } else if (root_type_ == ArrayType) {
    AST_Array* array_node = dynamic_cast<AST_Array*>(root_);
    size_t array_dimension_count = array_node->n_dims();
    if (array_dimension_count > 1) {
      throw Error(root_, "using multidimensional arrays as keys is unsupported.");
    }
    size_t element_count = array_node->dims()[0]->ev()->u.ulval;
    AST_Type* type_node = array_node->base_type();
    AST_Type* unaliased_type_node = type_node->unaliased_type();
    for (; pos_ < element_count; ++pos_) {
      child_ = new Iterator(unaliased_type_node, *this);
      Iterator& child = *child_;
      if (child == Iterator()) {
        delete child_;
        child_ = 0;
        throw Error(array_node, "array type is marked as key, but it's base type "
          "does not contain any keys.");
      } else {
        current_value_ = *child;
        return *this;
      }
      return *this;
    }

  // If we are a union, use self if we have a key
  } else if (root_type_ == UnionType) {
    if (pos_ == 0) { // Only Allow One Iteration
      pos_ = 1;
      AST_Union* union_node = dynamic_cast<AST_Union*>(root_);
      if (be_global->has_key(union_node)) {
        current_value_ = root_;
        return *this;
      } else {
        throw Error(union_node, "union type is marked as key, "
          "but it's discriminator isn't");
      }
    }

  // If we are a primitive type, use self
  } else if (root_type_ == PrimitiveType) {
    if (pos_ == 0) { // Only Allow One Iteration
      pos_ = 1;
      current_value_ = root_;
      return *this;
    }
  }

  // Nothing left to do, set this to null
  *this = Iterator();

  return *this;
}

SampleKeys::Iterator SampleKeys::Iterator::operator++(int)
{
  Iterator prev(*this);
  ++(*this);
  return prev;
}

SampleKeys::Iterator::value_type SampleKeys::Iterator::operator*() const
{
  return current_value_;
}

bool SampleKeys::Iterator::operator==(const SampleKeys::Iterator& other) const
{
  return
    root_ == other.root_ &&
    root_type_ == other.root_type_ &&
    parents_root_type_ == other.parents_root_type_ &&
    pos_ == other.pos_ &&
    current_value_ == other.current_value_ &&
    level_ == other.level_ &&
    (
      (child_ && other.child_) ? *child_ == *other.child_ : child_ == other.child_
    );
}

bool SampleKeys::Iterator::operator!=(const SampleKeys::Iterator& other) const
{
  return !(*this == other);
}

std::string SampleKeys::Iterator::path()
{
  std::stringstream ss;
  path_i(ss);
  return ss.str();
}

void SampleKeys::Iterator::path_i(std::stringstream& ss)
{
  if (root_type_ == StructureType) {
    AST_Structure* struct_root = dynamic_cast<AST_Structure*>(root_);
    AST_Field** field_ptrptr;
    struct_root->field(field_ptrptr, child_ ? pos_ : pos_ - 1);
    AST_Field* field = *field_ptrptr;
    ss << (level_ ? "." : "") << field->local_name()->get_string();
  } else if (root_type_ == UnionType) {
    ss << "._d()";
  } else if (root_type_ == ArrayType) {
    ss << '[' << pos_ << ']';
  } else if (root_type_ != PrimitiveType) {
    throw Error(root_, "Can't get path for invalid sample key iterator!");
  }
  if (child_) {
    child_->path_i(ss);
  }
}

void SampleKeys::Iterator::cleanup()
{
  delete child_;
}

SampleKeys::RootType SampleKeys::Iterator::root_type() const
{
  return child_ ? child_->root_type() : root_type_;
}

SampleKeys::RootType SampleKeys::Iterator::parents_root_type() const
{
  return child_ ? child_->parents_root_type() : parents_root_type_;
}

size_t SampleKeys::Iterator::level() const
{
  return child_ ? child_->level() : level_;
}

AST_Type* SampleKeys::Iterator::get_ast_type() const
{
  if (root_type() == UnionType) {
    return dynamic_cast<AST_Type*>(current_value_);
  }
  switch (parents_root_type()) {
  case StructureType:
    return dynamic_cast<AST_Field*>(current_value_)->field_type();
  case ArrayType:
    return dynamic_cast<AST_Type*>(current_value_);
  default:
    return 0;
  }
}

SampleKeys::SampleKeys(AST_Structure* root)
  : root_ (root),
    root_type_ (StructureType),
    counted_ (false)
{
  root_ = root;
}

SampleKeys::SampleKeys(AST_Union* root)
  : root_ (root),
    root_type_ (UnionType),
    counted_ (false)
{
  root_ = root;
}

SampleKeys::~SampleKeys()
{
}

SampleKeys::Iterator SampleKeys::begin()
{
  return Iterator(*this);
}

SampleKeys::Iterator SampleKeys::end()
{
  return Iterator();
}

AST_Decl* SampleKeys::root() const
{
  return root_;
}

SampleKeys::RootType SampleKeys::root_type() const
{
  return root_type_;
}

size_t SampleKeys::count()
{
  if (!counted_) {
    count_ = 0;
    Iterator finished = end();
    for (Iterator i = begin(); i != finished; ++i) {
      count_++;
    }
    counted_ = true;
  }
  return count_;
}
#endif
