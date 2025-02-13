import { Dropdown, Menu } from 'antd';
import DropdownWrapper, { DropdownMenus } from './styles/dropdown.style';
import WithDirection from '../../config/withDirection';

const WDDropdowns = DropdownWrapper(Dropdown);
const Dropdowns = WithDirection(WDDropdowns);

const WDDropdownButtons = DropdownWrapper(Dropdown.Button);
const DropdownButtons = WithDirection(WDDropdownButtons);
const DropdownMenu = DropdownMenus(Menu);
const MenuItem = DropdownMenus(Menu.Item);
const SubMenu = DropdownMenus(Menu.SubMenu);

export default Dropdowns;
export { DropdownButtons, DropdownMenu, MenuItem, SubMenu };
