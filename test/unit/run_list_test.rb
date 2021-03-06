class RunListTest < Minitest::Test
  def test_all_are_required
    builder.input_names << :foo

    run_list = builder.build

    assert_equal %w(foo⇒bar bar⇒baz baz⇒qux qux⇒res), run_list.node_names
    assert_includes run_list.dependencies, :foo
  end

  def test_discards_unnecessary_nodes
    builder['aba⇒cab'] = OpenStruct.new :required_dependencies => [:aba], :optional_dependencies => [], :provisions => [:cab]

    run_list = builder.build

    assert_equal %w(foo⇒bar bar⇒baz baz⇒qux qux⇒res), run_list.node_names
  end

  def test_supplying_dependencies
    builder.input_names << :baz

    run_list = builder.build

    assert_equal %w(baz⇒qux qux⇒res), run_list.node_names
    refute_includes run_list.dependencies, :foo
  end

  def test_nodes_that_modify
    assemble_builder modifying_nodes

    run_list = builder.build

    assert_equal %w(foo bar baz), run_list.node_names
  end

  def test_reorders_optional_deps_before_mandatory_deps_when_possible
    assemble_builder order_changes_because_of_optional_deps

    run_list = builder.build

    assert_equal %w(baz+foo bar+baz foo+bar final), run_list.node_names
    assert_equal [], run_list.required_dependencies
    assert_equal [:bar, :baz, :foo], run_list.optional_dependencies
  end

  def test_wrap_tsort_cycle_errors
    assemble_builder circular_dependency_tree

    error = assert_raises Orchestra::CircularDependencyError do
      builder.build
    end

    assert_equal(
      "Circular dependency detected! Check your dependencies/provides",
      error.message
    )
  end

  private

  def assemble_builder nodes = default_nodes
    @builder ||= begin
      builder = Orchestra::RunList::Builder.new :res
      builder.merge! nodes
      builder
    end
  end
  alias_method :builder, :assemble_builder

  def default_nodes
    {
      'foo⇒bar' => OpenStruct.new(:required_dependencies => [:foo], :provisions => [:bar], optional_dependencies: []),
      'bar⇒baz' => OpenStruct.new(:required_dependencies => [:bar], :provisions => [:baz], optional_dependencies: []),
      'baz⇒qux' => OpenStruct.new(:required_dependencies => [:baz], :provisions => [:qux], optional_dependencies: []),
      'qux⇒res' => OpenStruct.new(:required_dependencies => [:qux], :provisions => [:res], optional_dependencies: []),
    }
  end

  def modifying_nodes
    {
      'foo' => OpenStruct.new(:required_dependencies => [:shared], :provisions => [:shared], optional_dependencies: []),
      'bar' => OpenStruct.new(:required_dependencies => [:shared], :provisions => [:shared], optional_dependencies: []),
      'baz' => OpenStruct.new(:required_dependencies => [:shared], :provisions => [:shared, :res], optional_dependencies: []),
    }
  end

  def circular_dependency_tree
    {
      'foo+bar' => OpenStruct.new(
        :optional_dependencies => [:bar],
        :required_dependencies => [:foo],
        :provisions => [:aba]
      ),
      'bar+baz' => OpenStruct.new(
        :optional_dependencies => [:foo],
        :required_dependencies => [:bar],
        :provisions => [:cab],
      ),
      'final'   => OpenStruct.new(
        :optional_dependencies => [],
        :required_dependencies => [:aba, :cab],
        :provisions => [:res],
      )
    }
  end

  def order_changes_because_of_optional_deps
    {
      'foo+bar' => OpenStruct.new(
        :optional_dependencies => [],
        :required_dependencies => [:foo, :bar],
        :provisions => [:aba]
      ),
      'bar+baz' => OpenStruct.new(
        :optional_dependencies => [:bar],
        :required_dependencies => [:baz],
        :provisions => [:cab],
      ),
      'baz+foo' => OpenStruct.new(
        :optional_dependencies => [:baz, :foo],
        :required_dependencies => [],
        :provisions => [:bra],
      ),
      'final'   => OpenStruct.new(
        :optional_dependencies => [],
        :required_dependencies => [:aba, :cab, :bra],
        :provisions => [:res],
      ),
    }
  end
end
