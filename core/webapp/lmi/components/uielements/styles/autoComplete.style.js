import styled from 'styled-components';
import { palette } from 'styled-theme';

const AntAutoComplete = ComponentName => styled(ComponentName)`
  width: 100%;

  &.ant-select {
    .ant-select-selection {
      &.ant-select-selection--single {
        height: 35px;

        .ant-select-selection__rendered {
          line-height: 35px;
          margin: 0;

          .ant-select-selection__placeholder,
          .ant-select-search__field__placeholder {
            top: 8px;
            margin: 0 10px;
            left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
            right: ${props =>
              props['data-rtl'] === 'rtl' ? '9px' : 'inherit'};
            color: ${palette('grayscale', 1)};
          }

          .ant-input {
            padding: 4px 10px;
            width: 100%;
            height: 35px;
            font-size: 13px;
            text-align: ${props =>
              props['data-rtl'] === 'rtl' ? 'right' : 'left'};
            line-height: 1.5;
            color: ${palette('text', 1)};
            border: 1px solid ${palette('border', 0)};
            transition: all 0.3s;

            &:focus {
              border-color: ${palette('primary', 0)};
              outline: 0;
              box-shadow: 0 0 0 2px ${palette('primary', 3)};
            }

            &:hover {
              border-color: ${palette('primary', 0)};
            }
          }
        }
      }
    }

    .ant-select-search__field {
      padding: 0 10px;
    }
  }
`;

const AntAutoCompleteOption = ComponentName => styled(ComponentName)`
  color: #000000;
`;

export { AntAutoComplete, AntAutoCompleteOption };
