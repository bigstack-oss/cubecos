import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius } from '../../../config/style-util';

const AntDatePicker = ComponentName => styled(ComponentName)`
  .ant-input {
    padding: 4px 10px;
    width: 100%;
    height: 35px;
    cursor: text;
    font-size: 13px;
    line-height: 1.5;
    color: ${palette('text', 1)};
    background-color: #fff;
    background-image: none;
    border: 1px solid ${palette('border', 0)};
    ${borderRadius('4px')};
    ${transition()};

    &:focus {
      border-color: ${palette('primary', 0)};
    }

    &::-webkit-input-placeholder {
      color: ${palette('grayscale', 0)};
    }

    &:-moz-placeholder {
      color: ${palette('grayscale', 0)};
    }

    &::-moz-placeholder {
      color: ${palette('grayscale', 0)};
    }
    &:-ms-input-placeholder {
      color: ${palette('grayscale', 0)};
    }
  }
`;

export default AntDatePicker;
