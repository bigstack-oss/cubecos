import notification from './feedback/notification';

export default (type, message, description) => {
  notification[type]({
    message,
    description
  });
};
