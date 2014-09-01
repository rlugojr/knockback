{_, ko} = kb = require './kb'

# @nodoc
module.exports = class TypedValue
  constructor: (@create_options) ->
    @_vo = ko.observable(null) # create a value observable for the first dependency

  destroy: ->
    @__kb_released = true
    if previous_value = @__kb_value
      @__kb_value = null
      if @create_options.store and kb.utils.wrappedCreator(previous_value) then @create_options.store.release(previous_value) else kb.release(previous_value)
    @create_options = null

  value: -> ko.utils.unwrapObservable(@_vo())
  rawValue: -> return @__kb_value

  valueType: (model, key) ->
    new_value = kb.getValue(model, key)
    @value_type or @_updateValueObservable(new_value) # create so we can check the type
    return @value_type

  update: (new_value) ->
    return if @__kb_released # destroyed, nothing to do

    # determine the new type
    (new_value isnt undefined) or (new_value = null) # ensure null instead of undefined
    new_type = kb.utils.valueType(new_value)

    (@__kb_value = @value_type = undefined) if @__kb_value?.__kb_released
    value = @__kb_value

    switch @value_type
      when kb.TYPE_COLLECTION
        return value(new_value) if @value_type is kb.TYPE_COLLECTION and new_type is kb.TYPE_ARRAY
        if new_type is kb.TYPE_COLLECTION or _.isNull(new_value)
          # extract the collection
          new_value = kb.peek(new_value.collection) if new_value and not kb.isCollection(new_value) and _.isFunction(new_value.collection)

          if _.isFunction(value.collection) # and (not @create_options.store or @create_options.store.canReuse(value))
            value.collection(new_value) if kb.peek(value.collection) isnt new_value
          else
            @_updateValueObservable(new_value) if kb.utils.wrappedObject(value) isnt new_value
          return

      when kb.TYPE_MODEL
        if new_type is kb.TYPE_MODEL or _.isNull(new_value)
          # extract the model
          if new_value and not kb.isModel(new_value)
            new_observable = new_value
            new_value = if _.isFunction(new_value.model) then kb.peek(new_value.model) else kb.utils.wrappedObject(new_value)
            @_updateValueObservable(new_value, new_observable)
            return

          if _.isFunction(value.model) and (not @create_options.store or @create_options.store.canReuse(value))
            value.model(new_value) if kb.peek(value.model) isnt new_value
          else
            @_updateValueObservable(new_value) if kb.utils.wrappedObject(value) isnt new_value
          return

    if @value_type is new_type and not _.isUndefined(@value_type)
      value(new_value) if kb.peek(value) isnt new_value
    else
      @_updateValueObservable(new_value) if kb.peek(value) isnt new_value

  _updateValueObservable: (new_value, new_observable) ->
    create_options = @create_options
    creator = create_options.creator = kb.utils.inferCreator(new_value, create_options.factory, create_options.path)
    @value_type = kb.TYPE_UNKNOWN
    [previous_value, @__kb_value] = [@__kb_value, undefined]

    if new_observable
      value = new_observable
      create_options.store.register(new_value, new_observable, creator) if create_options.store

    # found a creator
    else if creator
      # have the store, use it to create
      if create_options.store
        value = create_options.store.findOrCreate(new_value, create_options)

      # create manually
      else
        if creator.models_only
          value = new_value
          @value_type = kb.TYPE_SIMPLE
        else if creator.create
          value = creator.create(new_value, create_options)
        else
          value = new creator(new_value, create_options)

    # create and cache the type
    else
      if _.isArray(new_value)
        @value_type = kb.TYPE_ARRAY
        value = ko.observableArray(new_value)
      else
        @value_type = kb.TYPE_SIMPLE
        value = ko.observable(new_value)

    # determine the type
    if @value_type is kb.TYPE_UNKNOWN
      if not ko.isObservable(value) # a view model, recognize view_models as non-observable
        @value_type = kb.TYPE_MODEL
        kb.utils.wrappedObject(value, new_value) if typeof(value.model) isnt 'function' # manually cache the model to check for changes later
      else if value.__kb_is_co
        @value_type = kb.TYPE_COLLECTION
      else
        @value_type = kb.TYPE_SIMPLE

    # release previous
    if previous_value
      if @create_options.store and kb.utils.wrappedCreator(previous_value) then @create_options.store.release(previous_value) else kb.release(previous_value)

    # store the value
    @__kb_value = value
    @_vo(value)
