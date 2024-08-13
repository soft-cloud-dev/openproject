import { ApplicationController } from 'stimulus-use';

export default class LoadAngularController extends ApplicationController {
  // initialize() {
  //   alert('initialized controller wohooo');
  // }

  connect() {
    alert('YEAH, connected!');
  }

  disconnect() {
    alert('disconnected!!!');
  }
}
