import React from 'react';
import classNames from 'classnames';
import { Icon } from 'antd';

const Toggle = ({ clickHandler, text, icon, active, large }) => {
  const buttonClass = classNames({
    buttonToggle: true,
    noIcon: !icon,
    active,
    large,
  });
  const iconClass = `${icon}`;

  return (
    <button className={`isoControlBtn ${buttonClass}`} onClick={clickHandler}>
      <Icon type={iconClass} />
      {text}
    </button>
  );
};

export default Toggle;
