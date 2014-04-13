chai = require 'chai'
{asyncCatch} = require './common'

{expect} = chai
chai.should()

deptree = require '../src/index'
tree = null

describe 'Tree constructor', ->
	it 'should use the linear updater as its default updater', ->
		tree = deptree()

		tree.updater.should.equal deptree.linearUpdater

	it 'should accept an updater function as its only parameter', ->
		tree = deptree deptree.parallelUpdater

		tree.updater.should.equal deptree.parallelUpdater

	it 'should accept a string which maps to one of the default updaters', ->
		tree = deptree 'parallel'

		tree.updater.should.equal deptree.parallelUpdater

beforeEach ->
	tree = deptree()

describe 'Dependency tree', ->
	describe '#()', ->
		it 'should return an temporary node object
		    when given a string node name', ->

			node = tree 'A'

			expect(node).to.exist

			node.should.be.instanceof deptree.Node

		it 'should optionally take a second parameter
		    to be passed when the update event is emitted', (done) ->

			node = tree 'A', { 'candy': 'yes!' }

			tree.extras.should.deep.equal { 'A': { 'candy': 'yes!' } }

			node.onUpdate asyncCatch(done) (name, extra) ->
				extra.should.deep.equal { 'candy': 'yes!' }

				done()

			tree.update 'A'

	describe '#update()', ->
		it "should trigger update event for an updated node", (done) ->
			tree 'A'
			.onUpdate (name) ->
				name.should.equal 'A'

				done()

			tree.update 'A'

		it 'should trigger update event for dependencies before itself', (done) ->
			updatedB = false

			tree 'B'
			.onUpdate (name) ->
				updatedB = true

			tree 'A'
			.dependsOn 'B'
			.onUpdate asyncCatch(done) (name) ->
				updatedB.should.equal true, 'expected B to be updated before A'

				done()

			tree.update 'B'

	describe '#dependencies()', ->
		it 'should return the dependencies of the given node', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree 'B'
			.dependsOn 'G', 'Q'

			tree 'C'
			.dependsOn 'F'

			tree.dependencies('A').should.deep.equal ['B', 'C']
			tree.dependencies('B').should.deep.equal ['G', 'Q']
			tree.dependencies('C').should.deep.equal ['F']
			tree.dependencies('Q').should.deep.equal []

	describe '#dependents()', ->
		it 'should return the nodes depending on the given node', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree 'B'
			.dependsOn 'G', 'Q'

			tree 'C'
			.dependsOn 'F'

			tree.dependents('A').should.deep.equal []
			tree.dependents('B').should.deep.equal ['A']
			tree.dependents('C').should.deep.equal ['A']
			tree.dependents('Q').should.deep.equal ['B']

	describe '#buildUpdateQueue()', ->
		it 'should return an array of nodes in the order to update them in', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree 'B'
			.dependsOn 'G', 'Q'

			tree 'C'
			.dependsOn 'F'

			tree 'Q'
			.dependsOn 'C'

			tree.buildUpdateQueue 'F'
			.should.deep.equal ['F', 'C', 'A', 'Q', 'B']

			tree.buildUpdateQueue 'G'
			.should.deep.equal ['G', 'B', 'A']

			tree.buildUpdateQueue 'B'
			.should.deep.equal ['B', 'A']

	describe '#buildUpdateTree()', ->
		it 'should return a map of affected nodes mapped to their dependencies', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree 'B'
			.dependsOn 'G', 'Q'

			tree 'C'
			.dependsOn 'F'

			tree 'Q'
			.dependsOn 'C'

			tree.buildUpdateTree 'G'
			.should.deep.equal
				'G': []
				'B': ['G']
				'A': ['B']

	describe '#checkDependsOn()', ->
		it 'should return true if node 1 depends on node 2', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree.checkDependsOn('A', 'B').should.be.true

		it 'should return false if node 1 does not depend on node 2', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree 'D'
			.dependsOn 'C'

			tree.checkDependsOn('D', 'B').should.be.false

describe 'Updaters', ->
	describe 'Linear', ->
		it 'should trigger updates for nodes linearly - a
		    node should always be updated before its dependents', (done) ->

			tree = deptree deptree.linearUpdater

			updated = []

			tree 'A'
			.dependsOn 'B'
			.onUpdate -> updated.push 'A'

			tree 'B'
			.dependsOn 'G'
			.onUpdate -> updated.push 'B'

			tree 'G'
			.onUpdate -> updated.push 'G'

			tree.update 'G', asyncCatch(done) () ->

				updated.should.deep.equal ['G', 'B', 'A']

				done()

	describe 'Parallel', ->
		it 'should trigger updates for nodes as soon as all
		    its dependencies are done', (done) ->

			tree = deptree deptree.parallelUpdater

			updated = []

			listener = (name) -> updated.push name

			tree 'A'
			.dependsOn 'B', 'C'
			.onUpdate listener

			tree 'B'
			.dependsOn 'G'
			.onUpdate listener

			tree 'G'
			.dependsOn 'C'
			.onUpdate listener

			tree 'C'
			.onUpdate listener

			tree.update 'C', asyncCatch(done) () ->

				updated.should.deep.equal ['C', 'G', 'B', 'A']

				updated = []

				tree.update 'G', asyncCatch(done) () ->

					updated.should.deep.equal ['G', 'B', 'A']

					done()

describe 'Node', ->
	describe '#dependsOn()', ->
		it 'should add one or more dependencies', ->
			tree 'A'
			.dependsOn 'B', 'C'

			tree.dependentTree.should.deep.equal { 'B': ['A'], 'C': ['A'] }

		it 'should throw an error if a circular dependency is detected', ->
			tree 'A'
			.dependsOn 'B'

			(-> tree('B').dependsOn 'A').should.throw Error, /Circular dependency/

	describe '#onUpdate()', ->
		it 'should add an update listener', ->
			tree('A').onUpdate (name) ->

			tree.updateListeners.should.have.key 'A'

	describe 'update callbacks', ->
		it 'should complete synchronously by default', (done) ->
			updated = []

			tree 'A'
			.dependsOn 'B'
			.onUpdate ->
				updated.push 'A'

			tree 'B'
			.onUpdate ->
				updated.push 'B'

			tree.update 'B', asyncCatch(done) () ->
				updated.should.deep.equal ['B', 'A']

				done()

		it 'should complete asynchronously if requested', (done) ->
			updated = []

			tree 'A'
			.dependsOn 'B'
			.onUpdate (..., async) ->
				asyncDone = async()
				process.nextTick -> updated.push 'A'; asyncDone()

			tree 'B'
			.onUpdate (..., async) ->
				asyncDone = async()
				process.nextTick -> updated.push 'B'; asyncDone()

			tree.update 'B', asyncCatch(done) () ->
				updated.should.deep.equal ['B', 'A']

				done()