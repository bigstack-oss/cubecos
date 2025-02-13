import React, { Component } from 'react';
import { List } from 'immutable';
import ComposeAutoCompleteStyleWrapper from './composeAutoComplete.style';

function createArray(array) {
  if (array && array.length > 0) {
    return List(
      array.map(element => ({
        label: `${element.name}<${element.email}>`,
        value: `${element.name}<${element.email}>`
      }))
    );
  }
  return List();
}
export default class extends Component {
  constructor(props) {
    super(props);
    const { value, allMails } = this.props;
    this.state = {
      tags: createArray(allMails ? allMails : []),
      selected: createArray(value && value.length > 0 ? value.split(',') : [])
    };
  }
  render() {
    const { updateData, placeholder } = this.props;
    const { tags, selected } = this.state;
    const update = option => {
      const val = option
        .toJS()
        .map(elem => elem.value)
        .join(',');
      updateData(val);
    };
    const onSelect = tag => {
      const newTag = {
        label: tag.label,
        value: tag.value || tag.label
      };
      const val = selected.push(newTag);
      update(val);
      this.setState({ selected: val });
    };
    const removeTag = tag => {
      const val = selected.filter(t => t.value !== tag.value);
      update(val);
      this.setState({ selected: val });
    };
    const optionsTag = {
      tags: tags.toJS(),
      selected: selected.toJS(),
      onSelect,
      removeTag,
      placeholder,
      backspaceDelete: true
    };
    return <ComposeAutoCompleteStyleWrapper className="isoEmailInputWrapper" />;
  }
}
