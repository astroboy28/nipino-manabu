// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form     = GlobalKey<FormState>();
  final _unCtrl   = TextEditingController();
  final _emCtrl   = TextEditingController();
  final _pwCtrl   = TextEditingController();
  final _pw2Ctrl  = TextEditingController();
  bool _obscure   = true;

  @override void dispose() {
    _unCtrl.dispose(); _emCtrl.dispose();
    _pwCtrl.dispose(); _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok   = await auth.register(_unCtrl.text, _emCtrl.text, _pwCtrl.text);
    if (ok && mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Row(children: [
                  Container(width:40,height:40,
                    decoration: BoxDecoration(color:AppColors.red,borderRadius:BorderRadius.circular(8)),
                    child: const Center(child: Text('日',style: TextStyle(fontFamily:'NotoSansJP',fontSize:20,fontWeight:FontWeight.w700,color:Colors.white)))),
                  const SizedBox(width:10),
                  RichText(text:const TextSpan(style:TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.ink),children:[
                    TextSpan(text:'Nipino-'),
                    TextSpan(text:'Manabu',style:TextStyle(color:AppColors.red)),
                  ])),
                ]),
                const SizedBox(height:32),
                const Text('Create account',style:TextStyle(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.ink)),
                const SizedBox(height:6),
                const Text('Start your Japanese learning journey today.',style:TextStyle(fontSize:13,color:AppColors.muted)),
                const SizedBox(height:28),

                if (auth.error != null) ...[
                  Container(
                    padding:const EdgeInsets.all(12),
                    decoration:BoxDecoration(color:AppColors.redLight,border:const Border(left:BorderSide(color:AppColors.red,width:3)),borderRadius:BorderRadius.circular(4)),
                    child:Text(auth.error!,style:const TextStyle(color:AppColors.red,fontSize:13))),
                  const SizedBox(height:14),
                ],

                TextFormField(controller:_unCtrl,
                  decoration:const InputDecoration(labelText:'Username',prefixIcon:Icon(Icons.person_outline,size:18)),
                  validator:(v){
                    if(v==null||v.isEmpty) return 'Username required';
                    if(v.length<3) return 'At least 3 characters';
                    if(!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(v)) return 'Letters, numbers, _ . - only';
                    return null;
                  }),
                const SizedBox(height:12),
                TextFormField(controller:_emCtrl,keyboardType:TextInputType.emailAddress,
                  decoration:const InputDecoration(labelText:'Email address',prefixIcon:Icon(Icons.email_outlined,size:18)),
                  validator:(v){
                    if(v==null||v.isEmpty) return 'Email required';
                    if(!v.contains('@')) return 'Invalid email';
                    return null;
                  }),
                const SizedBox(height:12),
                TextFormField(controller:_pwCtrl,obscureText:_obscure,
                  decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outlined,size:18),
                    suffixIcon:IconButton(icon:Icon(_obscure?Icons.visibility_off:Icons.visibility,size:18),
                      onPressed:()=>setState(()=>_obscure=!_obscure))),
                  validator:(v){
                    if(v==null||v.length<8) return 'At least 8 characters';
                    if(!v.contains(RegExp(r'[A-Z]'))) return 'Needs an uppercase letter';
                    if(!v.contains(RegExp(r'[0-9]'))) return 'Needs a number';
                    return null;
                  }),
                const SizedBox(height:12),
                TextFormField(controller:_pw2Ctrl,obscureText:_obscure,
                  decoration:const InputDecoration(labelText:'Confirm password',prefixIcon:Icon(Icons.lock_outlined,size:18)),
                  validator:(v){
                    if(v!=_pwCtrl.text) return 'Passwords do not match';
                    return null;
                  }),
                const SizedBox(height:20),
                ElevatedButton(
                  onPressed:auth.loading?null:_submit,
                  child:auth.loading
                    ?const SizedBox(width:20,height:20,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
                    :const Text('Create account')),
                const SizedBox(height:16),
                Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                  const Text('Already have an account? ',style:TextStyle(color:AppColors.muted,fontSize:13)),
                  GestureDetector(onTap:()=>Navigator.pop(context),
                    child:const Text('Sign in',style:TextStyle(color:AppColors.red,fontSize:13,fontWeight:FontWeight.w700))),
                ]),
                const SizedBox(height:24),
                const Center(child:Text('By registering you agree to our Terms of Service\nand Privacy Policy at nipino-manabu.com/privacy',
                  textAlign:TextAlign.center,style:TextStyle(fontSize:10,color:AppColors.muted2),)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
