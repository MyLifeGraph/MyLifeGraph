// Native modal supplies focus containment, background inertness and Escape.
const dialog=document.querySelector('#demo-dialog');
const launcher=document.querySelector('#demo-launch');
const closeButton=document.querySelector('#demo-close');
let scrollY=0;
let previousTop='';
let backdropPress=false;
launcher.addEventListener('click',()=>{
  if(dialog.open)return;
  scrollY=window.scrollY;
  previousTop=document.body.style.top;
  document.body.style.top=`-${scrollY}px`;
  document.documentElement.classList.add('demo-open');
  dialog.showModal();
  closeButton.focus({preventScroll:true});
});
closeButton.addEventListener('click',()=>dialog.close());
dialog.addEventListener('pointerdown',event=>{backdropPress=event.target===dialog;});
dialog.addEventListener('click',event=>{
  if(backdropPress&&event.target===dialog)dialog.close();
  backdropPress=false;
});
dialog.addEventListener('close',()=>{
  document.documentElement.classList.remove('demo-open');
  document.body.style.top=previousTop;
  window.scrollTo({top:scrollY,behavior:'instant'});
  launcher.focus({preventScroll:true});
});
