import React, { Component } from 'react';
import Button from './uielements/button';
import Popover from './uielements/popover';
import ColorChooserDropdown from './colorChooser.style';

export default class extends Component {
  constructor(props) {
    super(props);
    this.handleVisibleChange = this.handleVisibleChange.bind(this);
    this.hide = this.hide.bind(this);
    this.state = {
      visible: false
    };
  }
  hide() {
    this.setState({ visible: false });
  }
  handleVisibleChange() {
    this.setState({ visible: !this.state.visible });
  }
  render() {
    const { colors, seectedColor, changeColor } = this.props;
    const content = () => (
      <ColorChooserDropdown className="isoColorOptions">
        {colors.map((color, index) => {
          const onClick = () => {
            this.hide();
            changeColor(index);
          };
          const style = {
            background: color
          };
          return <Button key={index} onClick={onClick} style={style} />;
        })}
      </ColorChooserDropdown>
    );
    return (
      <Popover
        content={content()}
        trigger="click"
        visible={this.state.visible}
        onVisibleChange={this.handleVisibleChange}
      >
        <Button
          style={{ backgroundColor: colors[seectedColor] }}
          className="isoColorChooser"
        />
      </Popover>
    );
  }
}
