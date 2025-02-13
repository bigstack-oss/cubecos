import { Radio } from 'antd';
import AntRadiobox from './styles/radiobox.style';

const RadioBox = AntRadiobox(Radio);
const RadioGroup = AntRadiobox(Radio.Group);
const RadioButton = AntRadiobox(Radio.Button);

export default RadioBox;
export { RadioGroup, RadioButton };
