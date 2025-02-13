import { AutoComplete } from 'antd';
import { AntAutoComplete } from './styles/autoComplete.style';
import WithDirection from '../../config/withDirection';

const WDAutoCompletes = AntAutoComplete(AutoComplete);
const AutoCompletes = WithDirection(WDAutoCompletes);
const AutoCompleteOption = AutoComplete.Option;

export default AutoCompletes;
export { AutoCompleteOption };
